// Initialize Supabase + Stripe (skipped in Instagram's browser)
let db, stripe;
if (!window.__isInApp && window.supabase && window.Stripe) {
  db = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  stripe = Stripe(STRIPE_PUBLISHABLE_KEY);
}


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
const checkoutSection = document.getElementById('checkout-section');
const paymentArea = document.getElementById('payment-area');
const payBtn = document.getElementById('pay-btn');
const paymentError = document.getElementById('payment-error');
const sessionFullEl = document.getElementById('session-full');
const checkoutLocked = document.getElementById('checkout-locked');
const courtDots = document.getElementById('court-dots');
const waitlistFormSection = document.getElementById('waitlist-form-section');
const waitlistForm = document.getElementById('waitlist-form');
const waitlistBtn = document.getElementById('wl-btn');
const waitlistSection = document.getElementById('waitlist-section');
const waitlistList = document.getElementById('waitlist-list');
const weatherWidget = document.getElementById('weather-widget');
const nameInput = document.getElementById('player-name');
const emailInput = document.getElementById('player-email');

let currentSession = null;
let elements = null;
let countdownInterval = null;

// Stripe appearance config
const stripeAppearance = {
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
    '.Input': { border: '1px solid #374151', backgroundColor: '#1f2937', padding: '12px' },
    '.Input:focus': { border: '1px solid #f97316', boxShadow: '0 0 0 2px rgba(249, 115, 22, 0.2)' },
    '.Label': { color: '#9ca3af', marginBottom: '6px' },
  },
};

// Format date nicely
function formatDate(dateStr) {
  const date = new Date(dateStr + 'T00:00:00');
  return date.toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric' });
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
  const match = currentSession.time.match(/(\d+):(\d+)\s*(AM|PM)/i);
  if (!match) return null;
  let hours = parseInt(match[1], 10);
  const minutes = parseInt(match[2], 10);
  const period = match[3].toUpperCase();
  if (period === 'PM' && hours !== 12) hours += 12;
  if (period === 'AM' && hours === 12) hours = 0;
  const [year, month, day] = currentSession.date.split('-').map(Number);
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

// Weather widget
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

function showToast(message, type) {
  const toast = document.getElementById('toast');
  toast.textContent = message;
  toast.className = `toast toast-${type} show`;
  setTimeout(() => { toast.classList.remove('show'); }, 3000);
}

function isValidEmail(email) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

// Mount Stripe Elements immediately (deferred intent — no client_secret needed)
function mountPaymentForm() {
  elements = stripe.elements({
    mode: 'payment',
    amount: currentSession.price_cents,
    currency: 'usd',
    appearance: stripeAppearance,
  });

  // Card / payment method form
  const paymentElement = elements.create('payment', { layout: 'tabs' });
  paymentElement.mount('#payment-element');

  // Express Checkout (Apple Pay / Google Pay)
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
    await handlePayment();
  });

  expressElement.mount('#express-checkout-element');
  paymentArea.classList.remove('hidden');
}

// Handle payment — validate inputs, create PaymentIntent, confirm
async function handlePayment() {
  const name = nameInput.value.trim();
  const email = emailInput.value.trim();

  if (!name || !isValidEmail(email)) {
    paymentError.textContent = 'Please enter your name and a valid email.';
    paymentError.classList.remove('hidden');
    return;
  }

  payBtn.disabled = true;
  payBtn.innerHTML = '<span class="spinner"></span>';
  paymentError.classList.add('hidden');

  try {
    // Validate the payment form first
    const { error: submitError } = await elements.submit();
    if (submitError) {
      paymentError.textContent = submitError.message;
      paymentError.classList.remove('hidden');
      payBtn.disabled = false;
      payBtn.textContent = `RSVP & Pay $${(currentSession.price_cents / 100).toFixed(0)}`;
      return;
    }

    // Create PaymentIntent + RSVP record on the server
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

    // Confirm the payment with the server-created intent
    const { error } = await stripe.confirmPayment({
      elements,
      clientSecret: client_secret,
      confirmParams: {
        return_url: window.location.origin + '/success.html',
      },
    });

    // Only reaches here if there's an error (otherwise redirects)
    if (error) {
      paymentError.textContent = error.message;
      paymentError.classList.remove('hidden');
    }
  } catch (err) {
    console.error('Payment error:', err);
    paymentError.textContent = err.message || 'Something went wrong. Please try again.';
    paymentError.classList.remove('hidden');
  }

  payBtn.disabled = false;
  payBtn.textContent = `RSVP & Pay $${(currentSession.price_cents / 100).toFixed(0)}`;
}

// Pay button
payBtn.addEventListener('click', handlePayment);

// Load the next upcoming session
async function loadSession() {
  const today = new Date().toISOString().split('T')[0];

  const { data: activeSessions, error: activeError } = await db
    .from('sessions')
    .select('*')
    .gte('date', today)
    .neq('status', 'cancelled')
    .eq('payments_open', true)
    .order('date', { ascending: true })
    .limit(1);

  let sessions = activeSessions;
  let error = activeError;

  if (!sessions || sessions.length === 0) {
    const fallback = await db
      .from('sessions')
      .select('*')
      .gte('date', today)
      .neq('status', 'cancelled')
      .order('date', { ascending: true })
      .limit(1);
    sessions = fallback.data;
    error = fallback.error;
  }

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
  updatePaymentsState();
  startCountdown();
  loadWeather();
  await loadRSVPs();
  subscribeToRSVPs();
  subscribeToSession();
}

// Show/hide checkout based on payments_open flag
function updatePaymentsState() {
  if (currentSession.payments_open) {
    checkoutLocked.classList.add('hidden');
    checkoutSection.classList.remove('hidden');
    if (!elements) mountPaymentForm();
  } else {
    checkoutLocked.classList.remove('hidden');
    checkoutSection.classList.add('hidden');
  }
}

// Real-time session subscription (for shock drops)
function subscribeToSession() {
  if (!currentSession) return;
  db.channel('session-changes')
    .on('postgres_changes', {
      event: 'UPDATE', schema: 'public', table: 'sessions',
      filter: `id=eq.${currentSession.id}`,
    }, (payload) => {
      currentSession = payload.new;
      updatePaymentsState();
    })
    .subscribe();
}

// Load RSVPs
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

  const { data: waitlisted } = await db
    .from('public_rsvps')
    .select('*')
    .eq('session_id', currentSession.id)
    .eq('payment_status', 'waitlist');

  updateRSVPDisplay(rsvps || [], waitlisted || []);
}

// Update RSVP display
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
    checkoutSection.classList.add('hidden');
    checkoutLocked.classList.add('hidden');
    sessionFullEl.classList.add('hidden');
    waitlistFormSection.classList.remove('hidden');
    rsvpProgress.className = 'bg-gradient-to-r from-orange-500 to-orange-400 h-3.5 rounded-full progress-fill';
  } else if (count >= min) {
    rsvpMessage.textContent = `Session confirmed! ${max - count} spot${max - count !== 1 ? 's' : ''} left.`;
    rsvpProgress.className = 'bg-gradient-to-r from-green-500 to-green-400 h-3.5 rounded-full progress-fill';
    waitlistFormSection.classList.add('hidden');
    updatePaymentsState();
  } else {
    const needed = min - count;
    rsvpMessage.textContent = `${needed} more player${needed !== 1 ? 's' : ''} needed to confirm!`;
    rsvpProgress.className = 'bg-gradient-to-r from-orange-500 to-orange-400 h-3.5 rounded-full progress-fill';
    waitlistFormSection.classList.add('hidden');
    updatePaymentsState();
  }

  // Store for team randomizer
  currentRSVPs = rsvps;
  const teamRandomizer = document.getElementById('team-randomizer');
  if (count >= 4) {
    teamRandomizer.classList.remove('hidden');
  } else {
    teamRandomizer.classList.add('hidden');
  }

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

// Real-time RSVP subscription
function subscribeToRSVPs() {
  if (!currentSession) return;
  db.channel('rsvps-changes')
    .on('postgres_changes', {
      event: '*', schema: 'public', table: 'rsvps',
      filter: `session_id=eq.${currentSession.id}`,
    }, () => { loadRSVPs(); })
    .subscribe();
}

// Waitlist form
waitlistForm.addEventListener('submit', async (e) => {
  e.preventDefault();
  const name = document.getElementById('wl-name').value.trim();
  const email = document.getElementById('wl-email').value.trim();
  if (!name || !email) return;

  waitlistBtn.disabled = true;
  waitlistBtn.innerHTML = '<span class="spinner"></span>';

  try {
    const response = await db.functions.invoke('join-waitlist', {
      body: { session_id: currentSession.id, player_name: name, player_email: email },
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

// ---- Share button ----
document.getElementById('share-btn').addEventListener('click', async () => {
  const url = 'https://runsbyip.com';
  const text = 'Pickup basketball this Wednesday — RSVP and lock in your spot!';

  if (navigator.share) {
    try {
      await navigator.share({ title: 'RunsByIP', text, url });
    } catch (e) { /* user cancelled */ }
  } else {
    await navigator.clipboard.writeText(url);
    showToast('Link copied!', 'success');
  }
});

// ---- Team Randomizer ----
let currentRSVPs = [];

document.getElementById('randomize-btn').addEventListener('click', () => {
  if (currentRSVPs.length < 3) return;

  const shuffled = [...currentRSVPs].sort(() => Math.random() - 0.5);
  const size = Math.ceil(shuffled.length / 3);
  const team1 = shuffled.slice(0, size);
  const team2 = shuffled.slice(size, size * 2);
  const team3 = shuffled.slice(size * 2);

  document.getElementById('teams-display').classList.remove('hidden');

  document.getElementById('team-1').innerHTML = team1
    .map(r => `<p class="text-sm text-orange-300">${escapeHtml(r.player_name)}</p>`).join('');
  document.getElementById('team-2').innerHTML = team2
    .map(r => `<p class="text-sm text-blue-300">${escapeHtml(r.player_name)}</p>`).join('');
  document.getElementById('team-3').innerHTML = team3
    .map(r => `<p class="text-sm text-green-300">${escapeHtml(r.player_name)}</p>`).join('');
});

// ---- PWA Install ----
let deferredPrompt = null;

window.addEventListener('beforeinstallprompt', (e) => {
  e.preventDefault();
  deferredPrompt = e;
  document.getElementById('install-banner').classList.remove('hidden');
});

document.getElementById('install-btn').addEventListener('click', async () => {
  if (!deferredPrompt) return;
  deferredPrompt.prompt();
  const { outcome } = await deferredPrompt.userChoice;
  if (outcome === 'accepted') {
    document.getElementById('install-banner').classList.add('hidden');
  }
  deferredPrompt = null;
});

// Initialize (skip in Instagram's browser — inline fallback handles it)
if (db) {
  loadSession().catch(err => {
    console.error('Failed to load session:', err);
    showView('no-session');
  });
}
