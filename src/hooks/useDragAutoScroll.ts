'use client';

import { useEffect } from 'react';

export function useDragAutoScroll(mimeType = 'application/x-arta-item') {
  useEffect(() => {
    let frame: number | null = null;
    let speed = 0;

    function stop() {
      speed = 0;
      if (frame !== null) {
        window.cancelAnimationFrame(frame);
        frame = null;
      }
    }

    function tick() {
      if (speed === 0) {
        frame = null;
        return;
      }
      window.scrollBy(0, speed);
      frame = window.requestAnimationFrame(tick);
    }

    function update(event: DragEvent) {
      const types = event.dataTransfer ? Array.from(event.dataTransfer.types) : [];
      if (!types.includes(mimeType)) {
        stop();
        return;
      }

      const edge = 110;
      const maxSpeed = 16;
      const y = event.clientY;
      if (y < edge) {
        speed = -Math.max(4, Math.ceil(((edge - y) / edge) * maxSpeed));
      } else if (y > window.innerHeight - edge) {
        speed = Math.max(4, Math.ceil(((y - (window.innerHeight - edge)) / edge) * maxSpeed));
      } else {
        stop();
        return;
      }

      if (frame === null) frame = window.requestAnimationFrame(tick);
    }

    window.addEventListener('dragover', update);
    window.addEventListener('drop', stop);
    window.addEventListener('dragend', stop);
    return () => {
      stop();
      window.removeEventListener('dragover', update);
      window.removeEventListener('drop', stop);
      window.removeEventListener('dragend', stop);
    };
  }, [mimeType]);
}
