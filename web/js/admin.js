const db = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// DOM elements
const loginSection = document.getElementById('login-section');
const dashboard = document.getElementById('dashboard');
const headerActions = document.getElementById('header-actions');
const loginForm = document.getElementById('login-form');
const loginError = document.getElementById('login-error');
const createSessionForm = document.getElementById('create-session-form');
const sessionsList = document.getElementById('sessions-list');
const toast = document.getElementById('toast');

// Pre-fill date input to next Wednesday
function getNextWednesday() {
  const d = new Date();
  const day = d.getDay();
  const diff = (3 - day + 7) % 7 || 7;
  d.setDate(d.getDate() + diff);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}
document.getElementById('new-session-date').value = getNextWednesday();

// Toast helper
function showToast(message, type = 'success') {
  toast.textContent = message;
  toast.className = `toast toast-${type} show`;
  setTimeout(() => toast.classList.remove('show'), 3000);
}

// Show dashboard
function showDashboard() {
  loginSection.classList.add('hidden');
  dashboard.classList.remove('hidden');
  headerActions.classList.remove('hidden');
  loadSessions();
}

// Format date for display
function formatDate(dateStr) {
  const date = new Date(dateStr + 'T00:00:00');
  return date.toLocaleDateString('en-US', {
    weekday: 'short',
    month: 'short',
    day: 'numeric',
  });
}

// Check existing auth session
async function checkAuth() {
  const { data: { session } } = await db.auth.getSession();
  if (session) showDashboard();
}

// Login
loginForm.addEventListener('submit', async (e) => {
  e.preventDefault();
  loginError.classList.add('hidden');

  const email = document.getElementById('login-email').value;
  const password = document.getElementById('login-password').value;

  const { error } = await db.auth.signInWithPassword({ email, password });

  if (error) {
    loginError.textContent = error.message;
    loginError.classList.remove('hidden');
    return;
  }

  showDashboard();
});

// Logout
document.getElementById('logout-btn').addEventListener('click', async () => {
  await db.auth.signOut();
  location.reload();
});

// Load all sessions
async function loadSessions() {
  const { data: sessions, error } = await db
    .from('sessions')
    .select('*')
    .order('date', { ascending: false });

  if (error) {
    showToast('Failed to load sessions', 'error');
    return;
  }

  sessionsList.innerHTML = '';

  for (const session of sessions) {
    const { data: rsvps } = await db
      .from('rsvps')
      .select('*')
      .eq('session_id', session.id)
      .order('created_at', { ascending: true });

    sessionsList.appendChild(buildSessionCard(session, rsvps || []));
  }

  if (sessions.length === 0) {
    sessionsList.innerHTML = '<p class="text-muted text-center py-8">No sessions yet. Create one above.</p>';
  }
}

// Build a session card with RSVPs
function buildSessionCard(session, rsvps) {
  const card = document.createElement('div');
  card.className = 'bg-surface rounded-2xl border border-surface-light p-6';

  const paidRsvps = rsvps.filter(r => r.payment_status === 'paid' || r.payment_status === 'cash');
  const pendingRsvps = rsvps.filter(r => r.payment_status === 'pending');

  const statusColors = {
    open: 'bg-green-500/15 text-green-400',
    confirmed: 'bg-blue-500/15 text-blue-400',
    cancelled: 'bg-red-500/15 text-red-400',
  };

  card.innerHTML = `
    <div class="flex items-center justify-between mb-4">
      <div>
        <h3 class="font-semibold text-lg">${formatDate(session.date)}</h3>
        <p class="text-sm text-muted">${escapeHtml(session.time)} · ${escapeHtml(session.location)}</p>
      </div>
      <div class="flex items-center gap-2">
        <span class="px-2.5 py-1 rounded-full text-xs font-medium ${statusColors[session.status]}">${session.status}</span>
        <span class="text-sm text-muted">${paidRsvps.length}/${session.max_players}</span>
      </div>
    </div>

    ${session.status !== 'cancelled' ? `
    <div class="mb-4">
      <button onclick="toggleDrop('${session.id}', ${!session.payments_open})"
        class="w-full flex items-center justify-center gap-2 py-3 rounded-xl font-bold text-base transition-colors ${session.payments_open
          ? 'bg-red-600 active:bg-red-700 text-white'
          : 'bg-green-600 active:bg-green-700 text-white'
        }">
        ${session.payments_open
          ? '<svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"/></svg> Lock Payments'
          : '<svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 11V7a4 4 0 118 0m-4 8v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2z"/></svg> DROP IT \u2014 Open Payments'
        }
      </button>
      <p class="text-xs text-center mt-1.5 ${session.payments_open ? 'text-green-400' : 'text-muted-dark'}">
        ${session.payments_open ? 'Payments are LIVE' : 'Payments locked \u2014 players can see the session but can\u2019t pay yet'}
      </p>
    </div>
    ` : ''}

    ${rsvps.length > 0 ? `
      <div class="border-t border-surface-light pt-4">
        <h4 class="text-sm font-medium text-muted mb-2">RSVPs</h4>
        <div class="space-y-2">
          ${rsvps.map(rsvp => `
            <div class="flex items-center justify-between text-sm" data-rsvp-id="${rsvp.id}">
              <div>
                <span class="text-white">${escapeHtml(rsvp.player_name)}</span>
                <span class="text-muted ml-2">${escapeHtml(rsvp.player_email)}</span>
              </div>
              <div class="flex items-center gap-2">
                ${rsvp.payment_status === 'paid' ? `
                  <span class="text-green-400 text-xs font-medium">PAID</span>
                ` : rsvp.payment_status === 'cash' ? `
                  <span class="text-yellow-400 text-xs font-medium">CASH</span>
                ` : `
                  <span class="text-muted text-xs font-medium">PENDING</span>
                  <button onclick="markCash('${rsvp.id}')"
                    class="text-xs bg-yellow-600 hover:bg-yellow-500 text-white px-2 py-0.5 rounded transition-colors">
                    Mark Cash
                  </button>
                `}
              </div>
            </div>
          `).join('')}
        </div>
      </div>
    ` : '<p class="text-muted text-sm">No RSVPs yet.</p>'}

    ${pendingRsvps.length > 0 ? `
      <p class="text-xs text-muted mt-3">${pendingRsvps.length} pending payment${pendingRsvps.length !== 1 ? 's' : ''}</p>
    ` : ''}

    <div class="border-t border-surface-light mt-4 pt-4 flex gap-2">
      ${session.status === 'open' ? `
        <button onclick="updateSessionStatus('${session.id}', 'confirmed')"
          class="text-xs bg-blue-600 hover:bg-blue-500 text-white px-3 py-1.5 rounded-lg transition-colors">
          Confirm
        </button>
      ` : ''}
      ${session.status !== 'cancelled' ? `
        <button onclick="cancelSession('${session.id}')"
          class="text-xs bg-red-900 hover:bg-red-800 text-red-300 px-3 py-1.5 rounded-lg transition-colors">
          Cancel
        </button>
      ` : ''}
    </div>
  `;

  return card;
}

// Create session
createSessionForm.addEventListener('submit', async (e) => {
  e.preventDefault();

  const date = document.getElementById('new-session-date').value;
  const time = document.getElementById('new-session-time').value;
  const location = document.getElementById('new-session-location').value;
  const maxPlayers = parseInt(document.getElementById('new-session-max-players').value, 10);
  const priceDollars = parseInt(document.getElementById('new-session-price').value, 10);

  const { error } = await db.from('sessions').insert({
    date,
    time,
    location,
    max_players: maxPlayers,
    price_cents: priceDollars * 100,
    status: 'open',
  });

  if (error) {
    showToast('Failed to create session: ' + error.message, 'error');
    return;
  }

  showToast('Session created!');
  document.getElementById('new-session-date').value = getNextWednesday();
  document.getElementById('new-session-location').value = '';
  loadSessions();
});

// Update session status
async function updateSessionStatus(sessionId, status) {
  const { error } = await db
    .from('sessions')
    .update({ status })
    .eq('id', sessionId);

  if (error) {
    showToast('Failed to update session', 'error');
    return;
  }

  showToast(`Session ${status}!`);
  loadSessions();
}

// Cancel session
async function cancelSession(sessionId) {
  if (!confirm('Cancel this session? Players will see it as cancelled.')) return;
  await updateSessionStatus(sessionId, 'cancelled');
}

// Mark RSVP as cash payment
async function markCash(rsvpId) {
  const { error } = await db
    .from('rsvps')
    .update({ payment_status: 'cash' })
    .eq('id', rsvpId);

  if (error) {
    showToast('Failed to update payment', 'error');
    return;
  }

  showToast('Marked as cash');
  loadSessions();
}

// Toggle payments open/closed (shock drop)
async function toggleDrop(sessionId, open) {
  const { error } = await db
    .from('sessions')
    .update({ payments_open: open })
    .eq('id', sessionId);

  if (error) {
    showToast('Failed to toggle payments', 'error');
    return;
  }

  showToast(open ? 'PAYMENTS ARE LIVE!' : 'Payments locked', open ? 'success' : 'error');
  loadSessions();
}

function escapeHtml(str) {
  const div = document.createElement('div');
  div.textContent = str;
  return div.innerHTML;
}

// Init
checkAuth();
