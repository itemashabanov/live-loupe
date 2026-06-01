import Foundation

extension GalleryServer {
    static let galleryHTML = #"""
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
      <title>Photo Preview</title>
      <style>
        :root {
          color-scheme: dark;
          --bg: #0c0d0f;
          --panel: #16181d;
          --line: #2a2d35;
          --text: #f4f5f7;
          --muted: #a8afbd;
          --accent: #76d0ff;
        }

        * {
          box-sizing: border-box;
        }

        body {
          margin: 0;
          min-height: 100vh;
          background: var(--bg);
          color: var(--text);
          font: 15px/1.45 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", sans-serif;
        }

        header {
          position: sticky;
          top: 0;
          z-index: 2;
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: 16px;
          padding: calc(env(safe-area-inset-top) + 12px) 14px 12px;
          border-bottom: 1px solid var(--line);
          background: color-mix(in srgb, var(--bg) 90%, transparent);
          backdrop-filter: blur(16px);
        }

        h1 {
          margin: 0;
          font-size: 16px;
          font-weight: 650;
          letter-spacing: 0;
        }

        .meta {
          color: var(--muted);
          font-size: 13px;
          white-space: nowrap;
        }

        .grid {
          display: grid;
          grid-template-columns: repeat(auto-fill, minmax(132px, 1fr));
          gap: 8px;
          padding: 8px;
          padding-bottom: calc(env(safe-area-inset-bottom) + 8px);
        }

        .tile {
          display: block;
          width: 100%;
          padding: 0;
          border: 0;
          border-radius: 7px;
          overflow: hidden;
          background: var(--panel);
          aspect-ratio: 1;
          cursor: pointer;
        }

        .tile img {
          display: block;
          width: 100%;
          height: 100%;
          object-fit: cover;
        }

        .empty {
          display: grid;
          min-height: 64vh;
          place-items: center;
          padding: 28px;
          color: var(--muted);
          text-align: center;
        }

        .live {
          display: grid;
          width: 100vw;
          height: calc(100vh - 50px - env(safe-area-inset-top));
          place-items: center;
          padding: 0;
          background: #000;
        }

        .liveImage {
          display: block;
          max-width: 100vw;
          max-height: 100%;
          object-fit: contain;
        }

        .liveBadge {
          position: fixed;
          right: 12px;
          bottom: calc(env(safe-area-inset-bottom) + 12px);
          padding: 7px 10px;
          border: 1px solid #ffffff24;
          border-radius: 999px;
          background: #111111c8;
          color: #ffffffc8;
          font-size: 12px;
          font-weight: 650;
          backdrop-filter: blur(14px);
        }

        .viewer {
          position: fixed;
          inset: 0;
          z-index: 5;
          display: none;
          background: #000;
        }

        .viewer[data-open="true"] {
          display: grid;
          grid-template-rows: auto 1fr auto;
        }

        .viewerBar {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: 12px;
          padding: calc(env(safe-area-inset-top) + 10px) 12px 10px;
          background: linear-gradient(#000d, #0000);
        }

        .viewerTitle {
          overflow: hidden;
          color: #fff;
          font-size: 14px;
          font-weight: 600;
          text-overflow: ellipsis;
          white-space: nowrap;
        }

        .iconButton {
          display: inline-grid;
          width: 42px;
          height: 42px;
          flex: 0 0 auto;
          place-items: center;
          border: 1px solid #ffffff2e;
          border-radius: 50%;
          background: #151515b8;
          color: #fff;
          font-size: 22px;
          line-height: 1;
        }

        .stage {
          display: grid;
          min-height: 0;
          place-items: center;
          touch-action: pan-y;
        }

        .stage img {
          max-width: 100vw;
          max-height: 100%;
          object-fit: contain;
        }

        .viewerFooter {
          display: flex;
          align-items: center;
          justify-content: center;
          gap: 14px;
          min-height: 58px;
          padding: 8px 12px calc(env(safe-area-inset-bottom) + 10px);
          background: linear-gradient(#0000, #000d);
          color: #fff;
        }

        .counter {
          min-width: 74px;
          color: #ffffffb8;
          text-align: center;
          font-size: 13px;
        }
      </style>
    </head>
    <body>
      <header>
        <h1>Photo Preview</h1>
        <div class="meta" id="meta">Loading</div>
      </header>

      <main id="content" class="empty">Export JPEG previews into the selected folder.</main>

      <section class="viewer" id="viewer" aria-hidden="true">
        <div class="viewerBar">
          <div class="viewerTitle" id="viewerTitle"></div>
          <button class="iconButton" id="closeButton" aria-label="Close">×</button>
        </div>
        <div class="stage" id="stage">
          <img id="viewerImage" alt="">
        </div>
        <div class="viewerFooter">
          <button class="iconButton" id="prevButton" aria-label="Previous">‹</button>
          <div class="counter" id="counter"></div>
          <button class="iconButton" id="nextButton" aria-label="Next">›</button>
        </div>
      </section>

      <script>
        const content = document.getElementById('content');
        const meta = document.getElementById('meta');
        const viewer = document.getElementById('viewer');
        const viewerImage = document.getElementById('viewerImage');
        const viewerTitle = document.getElementById('viewerTitle');
        const counter = document.getElementById('counter');
        const stage = document.getElementById('stage');

        let images = [];
        let signature = '';
        let currentIndex = 0;
        let touchStartX = null;
        const LIVE_FILE = '__lr_live_preview.jpg';

        function imageURL(entry) {
          return `/file/${entry.id}?v=${entry.modified}-${entry.size}`;
        }

        function nextSignature(items) {
          return items.map((item) => `${item.id}:${item.modified}:${item.size}`).join('|');
        }

        function followModeRedirect(response) {
          const redirectPath = response.headers.get('X-Live-Loupe-Redirect');
          if (redirectPath) {
            window.location.replace(redirectPath);
            return true;
          }

          if (response.redirected && response.url) {
            window.location.replace(response.url);
            return true;
          }

          return false;
        }

        function render(items) {
          const liveEntry = items.find((entry) => entry.name === LIVE_FILE || entry.relativePath === LIVE_FILE);
          if (liveEntry) {
            renderLive(liveEntry);
            return;
          }

          images = items;
          meta.textContent = `${items.length} photo${items.length === 1 ? '' : 's'}`;

          if (!items.length) {
            content.dataset.mode = 'empty';
            content.className = 'empty';
            content.textContent = 'Export JPEG previews into the selected folder.';
            return;
          }

          content.dataset.mode = 'grid';
          content.className = 'grid';
          content.replaceChildren();

          items.forEach((entry, index) => {
            const tile = document.createElement('button');
            tile.className = 'tile';
            tile.dataset.index = String(index);
            tile.setAttribute('aria-label', entry.name);

            const image = document.createElement('img');
            image.src = imageURL(entry);
            image.alt = entry.name;
            image.loading = 'lazy';

            tile.append(image);
            content.append(tile);
          });
        }

        function renderLive(entry) {
          images = [entry];
          currentIndex = 0;
          meta.textContent = 'Live';

          if (content.dataset.mode !== 'live') {
            content.dataset.mode = 'live';
            content.className = 'live';
            content.replaceChildren();

            const image = document.createElement('img');
            image.id = 'liveImage';
            image.className = 'liveImage';
            image.alt = 'Live Lightroom preview';

            const badge = document.createElement('div');
            badge.className = 'liveBadge';
            badge.textContent = 'LIVE';

            content.append(image, badge);
          }

          const image = document.getElementById('liveImage');
          if (image && image.src !== new URL(imageURL(entry), window.location.href).href) {
            image.src = imageURL(entry);
          }

          if (viewer.dataset.open === 'true') {
            closeViewer();
          }
        }

        async function refresh() {
          try {
            const response = await fetch('/manifest.json', { cache: 'no-store' });
            if (followModeRedirect(response)) return;
            if (!response.ok) throw new Error('manifest');
            const items = await response.json();
            const updatedSignature = nextSignature(items);

            if (updatedSignature !== signature) {
              signature = updatedSignature;
              render(items);
              if (viewer.dataset.open === 'true') {
                currentIndex = Math.min(currentIndex, Math.max(images.length - 1, 0));
                updateViewer();
              }
            }
          } catch {
            meta.textContent = 'Offline';
          }
        }

        function openViewer(index) {
          currentIndex = index;
          viewer.dataset.open = 'true';
          viewer.setAttribute('aria-hidden', 'false');
          updateViewer();
        }

        function closeViewer() {
          viewer.dataset.open = 'false';
          viewer.setAttribute('aria-hidden', 'true');
          viewerImage.removeAttribute('src');
        }

        function updateViewer() {
          const entry = images[currentIndex];
          if (!entry) {
            closeViewer();
            return;
          }

          viewerImage.src = imageURL(entry);
          viewerImage.alt = entry.name;
          viewerTitle.textContent = entry.name;
          counter.textContent = `${currentIndex + 1} / ${images.length}`;
        }

        function move(step) {
          if (!images.length) return;
          currentIndex = (currentIndex + step + images.length) % images.length;
          updateViewer();
        }

        content.addEventListener('click', (event) => {
          const tile = event.target.closest('.tile');
          if (!tile) return;
          openViewer(Number(tile.dataset.index));
        });

        document.getElementById('closeButton').addEventListener('click', closeViewer);
        document.getElementById('prevButton').addEventListener('click', () => move(-1));
        document.getElementById('nextButton').addEventListener('click', () => move(1));

        stage.addEventListener('touchstart', (event) => {
          touchStartX = event.changedTouches[0].screenX;
        }, { passive: true });

        stage.addEventListener('touchend', (event) => {
          if (touchStartX === null) return;
          const delta = event.changedTouches[0].screenX - touchStartX;
          touchStartX = null;
          if (Math.abs(delta) < 44) return;
          move(delta > 0 ? -1 : 1);
        }, { passive: true });

        window.addEventListener('keydown', (event) => {
          if (viewer.dataset.open !== 'true') return;
          if (event.key === 'Escape') closeViewer();
          if (event.key === 'ArrowLeft') move(-1);
          if (event.key === 'ArrowRight') move(1);
        });

        refresh();
        setInterval(refresh, 250);
      </script>
    </body>
    </html>
    """#
}
