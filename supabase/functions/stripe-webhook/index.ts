import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import Stripe from "https://esm.sh/stripe@14?target=deno";

const JSON_HEADERS = { "Content-Type": "application/json" };

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: JSON_HEADERS,
  });
}

async function deletePendingReservation(
  supabase: ReturnType<typeof createClient>,
  paymentIntentId: string,
) {
  const { error } = await supabase
    .from("rsvps")
    .delete()
    .eq("stripe_session_id", paymentIntentId)
    .eq("payment_status", "pending");

  if (error) {
    console.error(`Failed to clear pending RSVP for ${paymentIntentId}:`, error);
  }
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, {
      apiVersion: "2023-10-16",
    });
    const webhookSecret = Deno.env.get("STRIPE_WEBHOOK_SECRET")!;
    const signature = req.headers.get("stripe-signature");

    if (!signature) {
      return jsonResponse({ error: "Missing stripe-signature header" }, 400);
    }

    const body = await req.text();

    let event: Stripe.Event;
    try {
      event = await stripe.webhooks.constructEventAsync(
        body,
        signature,
        webhookSecret,
      );
    } catch (err) {
      console.error("Webhook signature verification failed:", err instanceof Error ? err.message : err);
      return jsonResponse({ error: "Invalid signature" }, 400);
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    if (event.type === "payment_intent.payment_failed" || event.type === "payment_intent.canceled") {
      const paymentIntent = event.data.object as Stripe.PaymentIntent;
      await deletePendingReservation(supabase, paymentIntent.id);
      return jsonResponse({ received: true, cleared_pending: true });
    }

    if (event.type !== "payment_intent.succeeded") {
      return jsonResponse({ received: true, ignored: event.type });
    }

    const paymentIntent = event.data.object as Stripe.PaymentIntent;
    const metadataSessionId = paymentIntent.metadata?.session_id;
    const metadataRsvpId = paymentIntent.metadata?.rsvp_id;

    if (!metadataSessionId || !metadataRsvpId) {
      console.error(`PaymentIntent ${paymentIntent.id} missing required metadata`);
      return jsonResponse({ error: "Missing payment metadata" }, 400);
    }

    const { data: rsvp, error: rsvpError } = await supabase
      .from("rsvps")
      .select("id, session_id, payment_status, stripe_session_id")
      .eq("id", metadataRsvpId)
      .single();

    if (rsvpError || !rsvp) {
      console.error(`No RSVP found for PaymentIntent ${paymentIntent.id}:`, rsvpError);
      return jsonResponse({ received: true, orphaned_payment: true });
    }

    if (rsvp.session_id !== metadataSessionId || rsvp.stripe_session_id !== paymentIntent.id) {
      console.error(`Metadata mismatch for PaymentIntent ${paymentIntent.id}`);
      return jsonResponse({ error: "Payment metadata mismatch" }, 400);
    }

    if (rsvp.payment_status === "paid" || rsvp.payment_status === "cash") {
      return jsonResponse({ received: true, already_processed: true });
    }

    if (rsvp.payment_status !== "pending") {
      console.error(`Unexpected RSVP status ${rsvp.payment_status} for PaymentIntent ${paymentIntent.id}`);
      return jsonResponse({ received: true, ignored_status: rsvp.payment_status });
    }

    const { data: session, error: sessionError } = await supabase
      .from("sessions")
      .select("id, status")
      .eq("id", rsvp.session_id)
      .single();

    if (sessionError || !session) {
      console.error(`Session missing for RSVP ${rsvp.id}:`, sessionError);
      return jsonResponse({ error: "Session not found" }, 500);
    }

    if (session.status === "cancelled") {
      console.error(`Received payment for cancelled session ${session.id}`);
      return jsonResponse({ received: true, cancelled_session: true });
    }

    const { error: updateError } = await supabase
      .from("rsvps")
      .update({ payment_status: "paid" })
      .eq("id", rsvp.id)
      .eq("payment_status", "pending");

    if (updateError) {
      console.error("Failed to update RSVP:", updateError);
      return jsonResponse({ error: "Database update failed" }, 500);
    }

    console.log(`Payment confirmed for PaymentIntent ${paymentIntent.id}`);
    return jsonResponse({ received: true, marked_paid: true });
  } catch (err) {
    console.error("Webhook error:", err);
    return jsonResponse({ error: err instanceof Error ? err.message : "Unknown error" }, 500);
  }
});
