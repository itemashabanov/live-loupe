import Foundation

extension GalleryServer {
    static let screenHTML = #"""
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
      <title>Lightroom Screen Live</title>
      <style>
        :root {
          color-scheme: dark;
          --bg: #000;
          --text: #f7f7f8;
          --muted: #b8bcc6;
          --line: #ffffff24;
          --glass: #121318c8;
        }

        * {
          box-sizing: border-box;
        }

        body {
          margin: 0;
          min-height: 100vh;
          overflow: hidden;
          background: var(--bg);
          color: var(--text);
          font: 14px/1.4 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", sans-serif;
        }

        main {
          position: fixed;
          inset: 0;
          display: grid;
          place-items: center;
          background: #000;
        }

        #frame {
          display: block;
          width: 100vw;
          height: 100vh;
          object-fit: contain;
          user-select: none;
          -webkit-user-drag: none;
        }

        #frame[hidden] {
          display: none;
        }

        .emptyState {
          position: fixed;
          inset: 0;
          display: grid;
          place-items: center;
          padding: 28px;
          color: var(--muted);
          text-align: center;
        }

        .emptyState[hidden] {
          display: none;
        }

        .hud {
          position: fixed;
          left: 12px;
          right: 12px;
          bottom: calc(env(safe-area-inset-bottom) + 12px);
          z-index: 2;
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: 12px;
          padding: 8px 10px;
          border: 1px solid var(--line);
          border-radius: 999px;
          background: var(--glass);
          color: var(--muted);
          backdrop-filter: blur(18px);
        }

        .status {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }

        .live {
          display: inline-flex;
          align-items: center;
          gap: 7px;
          flex: 0 0 auto;
          color: var(--text);
          font-size: 12px;
          font-weight: 700;
          letter-spacing: 0;
        }

        .dot {
          width: 8px;
          height: 8px;
          border-radius: 50%;
          background: #35c759;
          box-shadow: 0 0 0 5px #35c75924;
        }
      </style>
    </head>
    <body>
      <main>
        <img id="frame" alt="Lightroom live screen preview" hidden>
        <div class="emptyState" id="emptyState">Waiting for Lightroom</div>
      </main>
      <div class="hud">
        <div class="live"><span class="dot"></span>LIVE</div>
        <div class="status" id="status">Connecting</div>
      </div>

      <script>
        const frame = document.getElementById('frame');
        const emptyState = document.getElementById('emptyState');
        const status = document.getElementById('status');
        let loaded = 0;
        let failed = 0;
        let running = true;
        let polling = false;
        let config = null;
        let streamURL = '';
        let fallbackTimer = 0;
        let configTimer = 0;

        async function loadConfig() {
          try {
            const response = await fetch('/screen-config.json', { cache: 'no-store' });
            if (!response.ok) throw new Error('config');
            const nextConfig = await response.json();

            if (!config || config.mode !== nextConfig.mode) {
              config = nextConfig;
              startStream();
            }
          } catch {
            status.textContent = 'Waiting for server';
          }
        }

        function startStream() {
          if (!running || !config) return;

          stopFallback();
          failed = 0;
          loaded = 0;
          frame.hidden = false;
          emptyState.hidden = true;
          streamURL = `/screen.mjpg?mode=${encodeURIComponent(config.mode)}&v=${Date.now()}`;
          frame.src = streamURL;
          status.textContent = `${config.title} · Streaming`;
        }

        function startFallback() {
          if (!running || polling || !config) return;
          polling = true;
          frame.hidden = true;
          emptyState.hidden = false;
          requestFrame();
        }

        function stopFallback() {
          polling = false;
          window.clearTimeout(fallbackTimer);
          fallbackTimer = 0;
        }

        function requestFrame() {
          if (!running || !polling || !config) return;

          const started = performance.now();
          const image = new Image();

          image.onload = () => {
            loaded += 1;
            failed = 0;
            frame.src = image.src;
            frame.hidden = false;
            emptyState.hidden = true;
            status.textContent = `${Math.round(performance.now() - started)} ms · ${loaded}`;
            fallbackTimer = window.setTimeout(requestFrame, config.activeDelayMilliseconds);
          };

          image.onerror = () => {
            failed += 1;
            const message = failed > 1
              ? 'Open Lightroom and allow Screen Recording on Mac'
              : 'Waiting for Lightroom';
            frame.hidden = true;
            emptyState.hidden = false;
            emptyState.textContent = message;
            status.textContent = message;
            fallbackTimer = window.setTimeout(requestFrame, 900);
          };

          image.src = `/screen.jpg?mode=${encodeURIComponent(config.mode)}&t=${Date.now()}`;
        }

        frame.addEventListener('load', () => {
          if (polling || !config) return;
          loaded += 1;
          failed = 0;
          frame.hidden = false;
          emptyState.hidden = true;
          status.textContent = `${config.title} · Streaming`;
        });

        frame.addEventListener('error', () => {
          if (polling) return;
          startFallback();
        });

        document.addEventListener('visibilitychange', () => {
          running = document.visibilityState === 'visible';
          if (running) {
            loadConfig();
          } else {
            stopFallback();
            frame.removeAttribute('src');
          }
        });

        loadConfig();
        configTimer = window.setInterval(loadConfig, 2000);
      </script>
    </body>
    </html>
    """#
}
