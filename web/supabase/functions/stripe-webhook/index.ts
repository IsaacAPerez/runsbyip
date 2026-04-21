import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import Stripe from "https://esm.sh/stripe@14?target=deno";

// Single source of truth for RSVP row creation: we only insert when Stripe
// confirms a payment succeeded. No pending rows, no reconciliation.
// The PaymentIntent.metadata carries session_id / player_name / player_email
// written by the create-checkout function.
//
// Capacity enforcement: we call insert_rsvp_if_capacity, which locks the
// session row inside a transaction. If the session is full when we get there
// (because someone else already took the last spot), we refund the charge.
Deno.serve(async (req: Request) => {
  try {
    const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, {
      apiVersion: "2023-10-16",
    });
    const webhookSecret = Deno.env.get("STRIPE_WEBHOOK_SECRET")!;

    const body = await req.text();
    const signature = req.headers.get("stripe-signature")!;

    let event: Stripe.Event;
    try {
      event = await stripe.webhooks.constructEventAsync(
        body,
        signature,
        webhookSecret,
      );
    } catch (err) {
      console.error(
        "Webhook signature verification failed:",
        err instanceof Error ? err.message : err,
      );
      return new Response(JSON.stringify({ error: "Invalid signature" }), {
        status: 400,
      });
    }

    if (event.type === "payment_intent.succeeded") {
      const paymentIntent = event.data.object as Stripe.PaymentIntent;
      const { session_id, player_name, player_email } =
        paymentIntent.metadata ?? {};

      if (!session_id || !player_name || !player_email) {
        console.error(
          `PaymentIntent ${paymentIntent.id} missing required metadata`,
          paymentIntent.metadata,
        );
        // Acknowledge so Stripe stops retrying — nothing we can recover without metadata.
        return ack();
      }

      const supabase = createClient(
        Deno.env.get("SUPABASE_URL")!,
        Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      );

      const { data, error } = await supabase
        .rpc("insert_rsvp_if_capacity", {
          p_session_id: session_id,
          p_player_name: player_name,
          p_player_email: player_email,
          p_stripe_session_id: paymentIntent.id,
        })
        .single();

      if (error) {
        // 23505 = unique_violation on stripe_session_id. Webhook retried for an
        // RSVP we already wrote — treat as success so Stripe stops retrying.
        if ((error as { code?: string }).code === "23505") {
          console.log(
            `RSVP for PaymentIntent ${paymentIntent.id} already exists — duplicate webhook`,
          );
          return ack();
        }

        console.error("insert_rsvp_if_capacity failed:", error);
        return new Response(
          JSON.stringify({ error: "Database insert failed" }),
          { status: 500 },
        );
      }

      const result = data as {
        inserted: boolean;
        confirmed_count: number;
        max_players: number;
      };

      if (!result.inserted) {
        // Session filled while this payment was in flight. Refund the charge
        // so the user isn't debited for a spot they didn't get.
        console.warn(
          `Session ${session_id} full (${result.confirmed_count}/${result.max_players}) — refunding PaymentIntent ${paymentIntent.id}`,
        );

        try {
          await stripe.refunds.create({
            payment_intent: paymentIntent.id,
            reason: "requested_by_customer",
            metadata: {
              refund_reason: "session_full",
              session_id,
            },
          });
        } catch (refundErr) {
          console.error(
            `Failed to refund PaymentIntent ${paymentIntent.id}:`,
            refundErr,
          );
          // Fall through and 500 so Stripe retries — the refund is the user's
          // money and we'd rather be noisy than silent.
          return new Response(
            JSON.stringify({ error: "Refund failed; will retry" }),
            { status: 500 },
          );
        }

        return ack();
      }

      console.log(`RSVP created for PaymentIntent ${paymentIntent.id}`);
    }

    return ack();
  } catch (err) {
    console.error("Webhook error:", err);
    return new Response(
      JSON.stringify({ error: err instanceof Error ? err.message : "unknown" }),
      { status: 500 },
    );
  }
});

function ack(): Response {
  return new Response(JSON.stringify({ received: true }), {
    headers: { "Content-Type": "application/json" },
  });
}
