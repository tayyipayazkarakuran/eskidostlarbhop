(() => {
    'use strict';

    const toast = document.getElementById('toast');
    let toastTimer;
    const showToast = (message) => {
        if (!toast) return;
        toast.textContent = message;
        toast.classList.add('is-visible');
        clearTimeout(toastTimer);
        toastTimer = setTimeout(() => toast.classList.remove('is-visible'), 2200);
    };

    document.querySelectorAll('[data-copy]').forEach((button) => {
        button.addEventListener('click', async () => {
            const value = button.getAttribute('data-copy') || '';
            try {
                await navigator.clipboard.writeText(value);
                showToast('Connect command copied.');
            } catch (_) {
                const input = document.createElement('textarea');
                input.value = value;
                document.body.appendChild(input);
                input.select();
                document.execCommand('copy');
                input.remove();
                showToast('Connect command copied.');
            }
        });
    });

    const search = document.querySelector('[data-map-search]');
    const cards = Array.from(document.querySelectorAll('[data-map-card]'));
    const empty = document.querySelector('[data-filter-empty]');
    if (search && cards.length) {
        search.addEventListener('input', () => {
            const query = search.value.trim().toLowerCase();
            let visible = 0;
            cards.forEach((card) => {
                const match = (card.getAttribute('data-map-name') || '').includes(query);
                card.hidden = !match;
                if (match) visible += 1;
            });
            if (empty) empty.hidden = visible !== 0;
        });
    }

    const configuredApiBase = document.body.getAttribute('data-api-base') || '';
    const apiBase = configuredApiBase || window.location.origin;
    const serverCard = document.querySelector('[data-server-card]');
    const ticker = document.querySelector('[data-live-ticker]');
    if (!serverCard && !ticker) return;

    const escapeHtml = (value) => String(value ?? '').replace(/[&<>'"]/g, (character) => ({
        '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;'
    })[character]);
    const number = (value) => Number.isFinite(Number(value)) ? Number(value) : 0;
    const setMapName = (element, value) => {
        if (!element) return;
        const name = String(value || 'Unavailable');
        element.textContent = name;
        element.classList.toggle('is-long', name.length > 11 && name.length <= 18);
        element.classList.toggle('is-very-long', name.length > 18);
    };
    const formatTime = (value) => {
        const ms = number(value);
        if (ms <= 0) return '--:--.---';
        const minutes = Math.floor(ms / 60000);
        const seconds = Math.floor((ms % 60000) / 1000);
        return `${minutes}:${String(seconds).padStart(2, '0')}.${String(ms % 1000).padStart(3, '0')}`;
    };
    const relative = (timestamp) => {
        const seconds = Math.max(0, Math.floor((Date.now() - number(timestamp)) / 1000));
        if (seconds < 60) return 'Just now';
        if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`;
        if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ago`;
        return `${Math.floor(seconds / 86400)}d ago`;
    };

    let refreshing = false;
    const refreshLive = async () => {
        if (refreshing || document.hidden) return;
        refreshing = true;
        try {
            const requests = [];
            if (serverCard) requests.push(fetch(`${apiBase}/api/status`, { headers: { Accept: 'application/json' } }));
            if (ticker) requests.push(fetch(`${apiBase}/api/live-ticker?limit=15`, { headers: { Accept: 'application/json' } }));
            const responses = await Promise.all(requests);
            let cursor = 0;
            if (serverCard) {
                const statusResponse = responses[cursor++];
                if (!statusResponse.ok) throw new Error('Status request failed');
                const status = await statusResponse.json();
                const game = status.game || {};
                serverCard.setAttribute('data-online', game.online ? '1' : '0');
                const state = serverCard.querySelector('[data-game-state]');
                const map = serverCard.querySelector('[data-game-map]');
                const players = serverCard.querySelector('[data-game-players]');
                const list = serverCard.querySelector('[data-game-list]');
                if (state) state.textContent = game.online ? 'ONLINE' : 'OFFLINE';
                setMapName(map, game.map || 'Unavailable');
                if (players) players.textContent = number(game.players);
                if (list) {
                    const playerList = Array.isArray(game.playerList) ? game.playerList.slice(0, 6) : [];
                    list.innerHTML = playerList.length
                        ? playerList.map((player) => `<span><i></i><b>${escapeHtml(player.name || 'unnamed')}</b><small>${Math.max(0, Math.round(number(player.duration) / 60))}m</small></span>`).join('')
                        : `<p>${game.online ? 'The server is clear. First run is yours.' : 'Player list unavailable.'}</p>`;
                }
            }
            if (ticker) {
                const tickerResponse = responses[cursor];
                if (!tickerResponse.ok) throw new Error('Ticker request failed');
                const rows = await tickerResponse.json();
                if (Array.isArray(rows) && rows.length) {
                    ticker.innerHTML = rows.map((row) => {
                        const tag = row.is_wr ? 'WR' : (row.is_pb ? 'PB' : 'FINISH');
                        return `<article class="ticker-item"><span class="ticker-tag tag-${tag.toLowerCase()}">${tag}</span><div><strong>${escapeHtml(row.player || 'Unknown player')}</strong><span>${escapeHtml(row.map || '—')} · ${escapeHtml(row.mode_label || '')}</span></div><time>${formatTime(row.time)}<small>${relative(row.timestamp)}</small></time></article>`;
                    }).join('');
                }
            }
        } catch (_) {
            // Keep the last server-rendered state when a background refresh fails.
        } finally {
            refreshing = false;
        }
    };

    window.setInterval(refreshLive, 20000);
})();
