// Initialize Supabase client
const db = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

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

let currentSession = null;

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

// Load the next upcoming session
async function loadSession() {
  const today = new Date().toISOString().split('T')[0];

  const { data: sessions, error } = await db
    .from('sessions')
    .select('*')
    .gte('date', today)
    .order('date', { ascending: true })
    .limit(1);

  if (error || !sessions || sessions.length === 0) {
    showView('no-session');
    return;
  }

  currentSession = sessions[0];

  if (currentSession.status === 'cancelled') {
    showView('cancelled-session');
    return;
  }

  // Populate session details
  sessionDate.textContent = formatDate(currentSession.date);
  sessionTime.textContent = currentSession.time;
  sessionLocation.textContent = currentSession.location;
  sessionPrice.textContent = `$${(currentSession.price_cents / 100).toFixed(0)}`;

  if (currentSession.status === 'confirmed') {
    sessionStatusBadge.textContent = 'Confirmed';
    sessionStatusBadge.className = 'px-3 py-1 rounded-full text-sm font-medium bg-blue-900 text-blue-300';
  }

  showView('session-card');
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

  updateRSVPDisplay(rsvps || []);
}

// Update the RSVP count, progress bar, and player list
function updateRSVPDisplay(rsvps) {
  const count = rsvps.length;
  const min = currentSession.min_players;
  const max = currentSession.max_players;
  const pct = Math.min((count / min) * 100, 100);

  rsvpCount.textContent = `${count}/${min}`;
  rsvpProgress.style.width = `${pct}%`;

  if (count >= max) {
    rsvpMessage.textContent = 'Session is full!';
    rsvpFormSection.classList.add('hidden');
    sessionFullEl.classList.remove('hidden');
  } else if (count >= min) {
    rsvpMessage.textContent = `Session confirmed! ${max - count} spot${max - count !== 1 ? 's' : ''} left.`;
    rsvpProgress.classList.remove('bg-orange-500');
    rsvpProgress.classList.add('bg-green-500');
  } else {
    const needed = min - count;
    rsvpMessage.textContent = `${needed} more player${needed !== 1 ? 's' : ''} needed to confirm!`;
  }

  // Player list
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

// Handle RSVP form submission
rsvpForm.addEventListener('submit', async (e) => {
  e.preventDefault();

  const name = document.getElementById('player-name').value.trim();
  const email = document.getElementById('player-email').value.trim();

  if (!name || !email) return;

  // Disable button, show loading
  rsvpBtn.disabled = true;
  rsvpBtn.innerHTML = '<span class="spinner"></span>';

  try {
    const response = await db.functions.invoke('create-checkout', {
      body: {
        session_id: currentSession.id,
        player_name: name,
        player_email: email,
      },
    });

    if (response.error) throw response.error;

    const { checkout_url } = response.data;
    if (checkout_url) {
      window.location.href = checkout_url;
    } else {
      throw new Error('No checkout URL returned');
    }
  } catch (err) {
    console.error('Checkout error:', err);
    rsvpBtn.disabled = false;
    rsvpBtn.textContent = `RSVP & Pay $${(currentSession.price_cents / 100).toFixed(0)}`;
    alert('Something went wrong. Please try again.');
  }
});

// Escape HTML to prevent XSS
function escapeHtml(str) {
  const div = document.createElement('div');
  div.textContent = str;
  return div.innerHTML;
}

// Initialize
loadSession();
