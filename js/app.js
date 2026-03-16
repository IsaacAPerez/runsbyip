// Initialize Supabase client
const db = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
const stripe = Stripe(STRIPE_PUBLISHABLE_KEY);

// DOM elements
const loadingEl = document.getElementById('loading');
const noSessionEl = document.getElementById('no-session');
const cancelledEl = document.getElementById('cancelled-session');
const sessionCard = document.getElementById('session-card');
const sessionDate = document.getElementById('session-date');
const sessionTime = document.getElementById('session-time');
const sessionLocation = document.getElementById('session-location');
const sessionPrice = document.getElementById('session-price');
const sessionStatusBadge = document.getElementById('session-status-badge');
const rsvpCount = document.getElementById('rsvp-count');
const rsvpProgress = document.getElementById('rsvp-progress');
const rsvpMessage = document.getElementById('rsvp-message');
const playerList = document.getElementById('player-list');
const rsvpFormSection = document.getElementById('rsvp-form-section');
const rsvpForm = document.getElementById('rsvp-form');
const rsvpBtn = document.getElementById('rsvp-btn');
const sessionFullEl = document.getElementById('session-full');
const paymentSection = document.getElementById('payment-section');
const paymentBackBtn = document.getElementById('payment-back-btn');
const payBtn = document.getElementById('pay-btn');
const paymentError = document.getElementById('payment-error');
const courtDots = document.getElementById('court-dots');
const waitlistFormSection = document.getElementById('waitlist-form-section');
const waitlistForm = document.getElementById('waitlist-form');
const waitlistBtn = document.getElementById('wl-btn');
const waitlistSection = document.getElementById('waitlist-section');
const waitlistList = document.getElementById('waitlist-list');
const weatherWidget = document.getElementById('weather-widget');

let currentSession = null;
let elements = null;
let countdownInterval = null;

// Format date nicely
function formatDate(dateStr) {
  const date = new Date(dateStr + 'T00:00:00');
  return date.toLocaleDateString('en-US', {
    weekday: 'long',
    month: 'long',
    day: 'numeric',
  });
}

// Show a specific view, hide others
function showView(viewId) {
  loadingEl.classList.add('hidden');
  noSessionEl.classList.add('hidden');
  cancelledEl.classList.add('hidden');
  sessionCard.classList.add('hidden');
  document.getElementById(viewId).classList.remove('hidden');
}

// Parse session date + time into a Date object
function getSessionDateTime() {
  if (!currentSession) return null;
  const timeStr = currentSession.time; // e.g. "7:00 PM" or "7:00PM"
  const dateStr = currentSession.date; // e.g. "2026-03-18"
  const match = timeStr.match(/(\d+):(\d+)\s*(AM|PM)/i);
  if (!match) return null;
  let hours = parseInt(match[1], 10);
  const minutes = parseInt(match[2], 10);
  const period = match[3].toUpperCase();
  if (period === 'PM' && hours !== 12) hours += 12;
  if (period === 'AM' && hours === 12) hours = 0;
  const [year, month, day] = dateStr.split('-').map(Number);
  return new Date(year, month - 1, day, hours, minutes, 0);
}

// Countdown timer
function startCountdown() {
  if (countdownInterval) clearInterval(countdownInterval);

  function update() {
    const target = getSessionDateTime();
    if (!target) return;
    const diff = target - new Date();

    if (diff <= 0) {
      document.getElementById('cd-days').textContent = '0';
      document.getElementById('cd-hours').textContent = '0';
      document.getElementById('cd-mins').textContent = '0';
      document.getElementById('cd-secs').textContent = '0';
      clearInterval(countdownInterval);
      return;
    }

    document.getElementById('cd-days').textContent = Math.floor(diff / 86400000);
    document.getElementById('cd-hours').textContent = Math.floor((diff % 86400000) / 3600000);
    document.getElementById('cd-mins').textContent = Math.floor((diff % 3600000) / 60000);
    document.getElementById('cd-secs').textContent = Math.floor((diff % 60000) / 1000);
  }

  update();
  countdownInterval = setInterval(update, 1000);
}

// Weather widget — Open-Meteo (free, no API key)
async function loadWeather() {
  if (!currentSession) return;
  try {
    const date = currentSession.date;
    const res = await fetch(
      `https://api.open-meteo.com/v1/forecast?latitude=34.05&longitude=-118.24&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max,weather_code&temperature_unit=fahrenheit&timezone=America/Los_Angeles&start_date=${date}&end_date=${date}`
    );
    const data = await res.json();
    if (!data.daily || !data.daily.time || data.daily.time.length === 0) return;

    const high = Math.round(data.daily.temperature_2m_max[0]);
    const low = Math.round(data.daily.temperature_2m_min[0]);
    const rainChance = data.daily.precipitation_probability_max[0];
    const code = data.daily.weather_code[0];
    const { icon, desc } = getWeatherInfo(code);

    document.getElementById('weather-icon').textContent = icon;
    document.getElementById('weather-temp').textContent = high;
    document.getElementById('weather-desc').textContent = desc;
    document.getElementById('weather-high').textContent = high;
    document.getElementById('weather-low').textContent = low;
    document.getElementById('weather-rain').textContent = rainChance > 0 ? `${rainChance}% rain` : '';

    weatherWidget.classList.remove('hidden');
  } catch (err) {
    console.error('Weather fetch error:', err);
  }
}

function getWeatherInfo(code) {
  if (code === 0) return { icon: '\u2600\uFE0F', desc: 'Clear' };
  if (code <= 3) return { icon: '\u26C5', desc: 'Partly Cloudy' };
  if (code <= 48) return { icon: '\uD83C\uDF2B\uFE0F', desc: 'Foggy' };
  if (code <= 55) return { icon: '\uD83C\uDF26\uFE0F', desc: 'Drizzle' };
  if (code <= 65) return { icon: '\uD83C\uDF27\uFE0F', desc: 'Rain' };
  if (code <= 75) return { icon: '\u2744\uFE0F', desc: 'Snow' };
  if (code <= 82) return { icon: '\uD83C\uDF27\uFE0F', desc: 'Showers' };
  return { icon: '\u26C8\uFE0F', desc: 'Thunderstorm' };
}

// Court dot visualization
const DOT_POSITIONS = [
  [20, 30], [80, 30], [50, 50], [30, 70], [70, 70],
  [15, 50], [85, 50], [40, 25], [60, 75], [50, 15],
  [25, 85], [75, 15], [35, 45], [65, 55], [45, 80],
];

function renderCourtDots(count, max) {
  courtDots.innerHTML = '';
  for (let i = 0; i < Math.min(count, max); i++) {
    const [x, y] = DOT_POSITIONS[i % DOT_POSITIONS.length];
    const dot = document.createElement('div');
    dot.className = 'court-dot';
    dot.style.left = `${x}%`;
    dot.style.top = `${y}%`;
    dot.style.animationDelay = `${i * 0.1}s`;
    courtDots.appendChild(dot);
  }
}

// Toast helper
function showToast(message, type) {
  const toast = document.getElementById('toast');
  toast.textContent = message;
  toast.className = `toast toast-${type} show`;
  setTimeout(() => { toast.classList.remove('show'); }, 3000);
}

// Load the next upcoming session
async function loadSession() {
  const today = new Date().toISOString().split('T')[0];

  const { data: sessions, error } = await db
    .from('sessions')
    .select('*')
    .gte('date', today)
    .neq('status', 'cancelled')
    .order('date', { ascending: true })
    .limit(1);

  if (error || !sessions || sessions.length === 0) {
    showView('no-session');
    return;
  }

  currentSession = sessions[0];

  sessionDate.textContent = formatDate(currentSession.date);
  sessionTime.textContent = currentSession.time;
  sessionLocation.textContent = currentSession.location;
  sessionPrice.textContent = `$${(currentSession.price_cents / 100).toFixed(0)}`;

  if (currentSession.status === 'confirmed') {
    sessionStatusBadge.textContent = 'Confirmed';
    sessionStatusBadge.className = 'px-3 py-1 rounded-full text-xs font-semibold uppercase tracking-wider bg-blue-500/15 text-blue-400 border border-blue-500/20';
  }

  showView('session-card');
  startCountdown();
  loadWeather();
  await loadRSVPs();
  subscribeToRSVPs();
}

// Load RSVPs for the current session
async function loadRSVPs() {
  if (!currentSession) return;

  const { data: rsvps, error } = await db
    .from('public_rsvps')
    .select('*')
    .eq('session_id', currentSession.id)
    .in('payment_status', ['paid', 'cash']);

  if (error) {
    console.error('Error loading RSVPs:', error);
    return;
  }

  // Load waitlisted players
  const { data: waitlisted } = await db
    .from('public_rsvps')
    .select('*')
    .eq('session_id', currentSession.id)
    .eq('payment_status', 'waitlist');

  updateRSVPDisplay(rsvps || [], waitlisted || []);
}

// Update the RSVP count, progress bar, court dots, and player lists
function updateRSVPDisplay(rsvps, waitlisted) {
  const count = rsvps.length;
  const max = currentSession.max_players;
  const min = currentSession.min_players;
  const pct = Math.min((count / max) * 100, 100);

  rsvpCount.textContent = `${count}/${max}`;
  rsvpProgress.style.width = `${pct}%`;

  renderCourtDots(count, max);

  if (count >= max) {
    rsvpMessage.textContent = 'Session is full!';
    rsvpFormSection.classList.add('hidden');
    sessionFullEl.classList.add('hidden');
    waitlistFormSection.classList.remove('hidden');
    rsvpProgress.className = 'bg-gradient-to-r from-orange-500 to-orange-400 h-3.5 rounded-full progress-fill';
  } else if (count >= min) {
    rsvpMessage.textContent = `Session confirmed! ${max - count} spot${max - count !== 1 ? 's' : ''} left.`;
    rsvpProgress.className = 'bg-gradient-to-r from-green-500 to-green-400 h-3.5 rounded-full progress-fill';
    waitlistFormSection.classList.add('hidden');
    rsvpFormSection.classList.remove('hidden');
  } else {
    const needed = min - count;
    rsvpMessage.textContent = `${needed} more player${needed !== 1 ? 's' : ''} needed to confirm!`;
    rsvpProgress.className = 'bg-gradient-to-r from-orange-500 to-orange-400 h-3.5 rounded-full progress-fill';
    waitlistFormSection.classList.add('hidden');
    rsvpFormSection.classList.remove('hidden');
  }

  // Confirmed players list
  playerList.innerHTML = '';
  rsvps.forEach((rsvp, i) => {
    const div = document.createElement('div');
    div.className = 'player-item flex items-center gap-2.5 text-sm text-gray-300';
    div.style.animationDelay = `${i * 0.05}s`;
    div.innerHTML = `
      <span class="w-5 h-5 rounded-full bg-green-500/15 flex items-center justify-center shrink-0">
        <svg class="w-3 h-3 text-green-400" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="3" d="M5 13l4 4L19 7"/></svg>
      </span>
      ${escapeHtml(rsvp.player_name)}`;
    playerList.appendChild(div);
  });

  // Waitlisted players
  if (waitlisted && waitlisted.length > 0) {
    waitlistSection.classList.remove('hidden');
    waitlistList.innerHTML = '';
    waitlisted.forEach((wl, i) => {
      const div = document.createElement('div');
      div.className = 'player-item flex items-center gap-2.5 text-sm text-gray-400';
      div.style.animationDelay = `${i * 0.05}s`;
      div.innerHTML = `
        <span class="w-5 h-5 rounded-full bg-yellow-500/15 flex items-center justify-center shrink-0">
          <svg class="w-3 h-3 text-yellow-400" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"/></svg>
        </span>
        ${escapeHtml(wl.player_name)}`;
      waitlistList.appendChild(div);
    });
  } else {
    waitlistSection.classList.add('hidden');
  }
}

// Subscribe to real-time RSVP changes
function subscribeToRSVPs() {
  if (!currentSession) return;

  db
    .channel('rsvps-changes')
    .on('postgres_changes', {
      event: '*',
      schema: 'public',
      table: 'rsvps',
      filter: `session_id=eq.${currentSession.id}`,
    }, () => {
      loadRSVPs();
    })
    .subscribe();
}

// Handle RSVP form — get PaymentIntent and show payment UI
rsvpForm.addEventListener('submit', async (e) => {
  e.preventDefault();

  const name = document.getElementById('player-name').value.trim();
  const email = document.getElementById('player-email').value.trim();
  if (!name || !email) return;

  rsvpBtn.disabled = true;
  rsvpBtn.innerHTML = '<span class="spinner"></span>';
  paymentError.classList.add('hidden');

  try {
    const response = await db.functions.invoke('create-checkout', {
      body: {
        session_id: currentSession.id,
        player_name: name,
        player_email: email,
      },
    });

    if (response.error) throw response.error;

    const { client_secret } = response.data;
    if (!client_secret) throw new Error('No client secret returned');

    // Create Stripe Elements with dark theme
    elements = stripe.elements({
      clientSecret: client_secret,
      appearance: {
        theme: 'night',
        variables: {
          colorPrimary: '#f97316',
          colorBackground: '#1f2937',
          colorText: '#ffffff',
          colorDanger: '#ef4444',
          borderRadius: '12px',
          fontFamily: 'Inter, system-ui, sans-serif',
          spacingUnit: '4px',
        },
        rules: {
          '.Input': {
            border: '1px solid #374151',
            backgroundColor: '#1f2937',
            padding: '12px',
          },
          '.Input:focus': {
            border: '1px solid #f97316',
            boxShadow: '0 0 0 2px rgba(249, 115, 22, 0.2)',
          },
          '.Label': {
            color: '#9ca3af',
            marginBottom: '6px',
          },
        },
      },
    });

    // Mount Payment Element (card form)
    const paymentElement = elements.create('payment', { layout: 'tabs' });
    paymentElement.mount('#payment-element');

    // Mount Express Checkout (Apple Pay / Google Pay)
    const expressElement = elements.create('expressCheckout', {
      buttonType: { applePay: 'plain', googlePay: 'plain' },
      buttonHeight: 48,
    });

    expressElement.on('ready', ({ availablePaymentMethods }) => {
      if (availablePaymentMethods) {
        document.getElementById('express-divider').classList.remove('hidden');
      }
    });

    expressElement.on('confirm', async () => {
      const { error } = await stripe.confirmPayment({
        elements,
        confirmParams: {
          return_url: window.location.origin + '/success.html',
        },
      });
      if (error) {
        paymentError.textContent = error.message;
        paymentError.classList.remove('hidden');
      }
    });

    expressElement.mount('#express-checkout-element');

    // Show payment section, hide form
    rsvpFormSection.classList.add('hidden');
    paymentSection.classList.remove('hidden');

  } catch (err) {
    console.error('Checkout error:', err);
    rsvpBtn.disabled = false;
    rsvpBtn.textContent = `RSVP & Pay $${(currentSession.price_cents / 100).toFixed(0)}`;
    paymentError.textContent = err.message || 'Something went wrong. Please try again.';
    paymentError.classList.remove('hidden');
  }
});

// Pay button — confirm card payment
payBtn.addEventListener('click', async () => {
  if (!elements) return;

  payBtn.disabled = true;
  payBtn.innerHTML = '<span class="spinner"></span>';
  paymentError.classList.add('hidden');

  const { error } = await stripe.confirmPayment({
    elements,
    confirmParams: {
      return_url: window.location.origin + '/success.html',
    },
  });

  if (error) {
    paymentError.textContent = error.message;
    paymentError.classList.remove('hidden');
  }

  payBtn.disabled = false;
  payBtn.textContent = `Pay $${(currentSession.price_cents / 100).toFixed(0)}`;
});

// Back button — return to RSVP form
paymentBackBtn.addEventListener('click', () => {
  paymentSection.classList.add('hidden');
  rsvpFormSection.classList.remove('hidden');
  rsvpBtn.disabled = false;
  rsvpBtn.textContent = `RSVP & Pay $${(currentSession.price_cents / 100).toFixed(0)}`;
  paymentError.classList.add('hidden');
  document.getElementById('payment-element').innerHTML = '';
  document.getElementById('express-checkout-element').innerHTML = '';
  document.getElementById('express-divider').classList.add('hidden');
  elements = null;
});

// Waitlist form handler
waitlistForm.addEventListener('submit', async (e) => {
  e.preventDefault();

  const name = document.getElementById('wl-name').value.trim();
  const email = document.getElementById('wl-email').value.trim();
  if (!name || !email) return;

  waitlistBtn.disabled = true;
  waitlistBtn.innerHTML = '<span class="spinner"></span>';

  try {
    const response = await db.functions.invoke('join-waitlist', {
      body: {
        session_id: currentSession.id,
        player_name: name,
        player_email: email,
      },
    });

    if (response.error) throw response.error;

    showToast("You're on the waitlist!", 'success');
    waitlistForm.reset();
    await loadRSVPs();
  } catch (err) {
    console.error('Waitlist error:', err);
    showToast(err.message || 'Something went wrong.', 'error');
  } finally {
    waitlistBtn.disabled = false;
    waitlistBtn.textContent = 'Join Waitlist';
  }
});

function escapeHtml(str) {
  const div = document.createElement('div');
  div.textContent = str;
  return div.innerHTML;
}

// Initialize
loadSession();
