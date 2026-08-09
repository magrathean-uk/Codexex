import { useEffect, useRef, useState, type PointerEvent as ReactPointerEvent } from "react";
import { GearIcon } from "@radix-ui/react-icons";
import { MobileScroll } from "./mobile";

const DEFAULT_PERCENT = 67;
const GLYPH_SET = "アカサタナハマヤラワ0123456789ABCDEF<>[]{}";

type MotionState = {
  sensorX: number;
  sensorY: number;
  pointerX: number;
  pointerY: number;
  sensorActive: boolean;
};

type MatrixCanvasProps = {
  percent: number;
  motion: React.MutableRefObject<MotionState>;
  reduceMotion: boolean;
};

export default function Prototype() {
  const [reduceMotion, setReduceMotion] = useState(false);
  const motionRef = useRef<MotionState>({
    sensorX: 0,
    sensorY: 0,
    pointerX: 0,
    pointerY: 0,
    sensorActive: false,
  });

  useEffect(() => {
    const media = window.matchMedia("(prefers-reduced-motion: reduce)");
    const update = () => setReduceMotion(media.matches);
    update();
    media.addEventListener("change", update);
    return () => media.removeEventListener("change", update);
  }, []);

  useEffect(() => {
    const handleOrientation = (event: DeviceOrientationEvent) => {
      const gamma = event.gamma ?? 0;
      const beta = event.beta ?? 45;
      motionRef.current.sensorX = clamp(gamma / 38, -1, 1);
      motionRef.current.sensorY = clamp((beta - 45) / 45, -1, 1);
      motionRef.current.sensorActive = true;
    };

    window.addEventListener("deviceorientation", handleOrientation, true);
    return () => window.removeEventListener("deviceorientation", handleOrientation, true);
  }, []);

  const handlePointerMove = (event: ReactPointerEvent<HTMLElement>) => {
    const rect = event.currentTarget.getBoundingClientRect();
    const x = ((event.clientX - rect.left) / rect.width) * 2 - 1;
    const y = ((event.clientY - rect.top) / rect.height) * 2 - 1;
    motionRef.current.pointerX = clamp(x, -1, 1);
    motionRef.current.pointerY = clamp(y, -1, 1);
  };

  return (
    <MobileScroll className="matrix-app">
      <main
        className="matrix-screen"
        aria-label="Matrix quota display"
        onPointerMove={handlePointerMove}
      >
        <MatrixCanvas percent={DEFAULT_PERCENT} motion={motionRef} reduceMotion={reduceMotion} />

        <header className="matrix-header">
          <button
            className="matrix-icon-button"
            type="button"
            aria-label="Matrix theme settings"
            data-scroll-drag="ignore"
          >
            <GearIcon width={19} height={19} />
          </button>
        </header>

        <section className="matrix-headline" aria-live="polite">
          <p className="matrix-percent" aria-label={`${DEFAULT_PERCENT} percent remaining`}>
            {DEFAULT_PERCENT}<span>%</span>
          </p>
        </section>
      </main>
    </MobileScroll>
  );
}

function MatrixCanvas({ percent, motion, reduceMotion }: MatrixCanvasProps) {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const percentRef = useRef(percent);
  const reduceMotionRef = useRef(reduceMotion);

  useEffect(() => {
    percentRef.current = percent;
  }, [percent]);

  useEffect(() => {
    reduceMotionRef.current = reduceMotion;
  }, [reduceMotion]);

  useEffect(() => {
    const canvas = canvasRef.current;
    const context = canvas?.getContext("2d");
    if (!canvas || !context) return;

    let width = 1;
    let height = 1;
    let pixelRatio = 1;
    let frame = 0;
    let lastTime = 0;
    let displayedPercent = percentRef.current;
    let nodes: SurfaceNode[] = [];
    let columns: MatrixColumn[] = [];

    const resize = () => {
      const rect = canvas.getBoundingClientRect();
      width = Math.max(1, rect.width);
      height = Math.max(1, rect.height);
      pixelRatio = Math.min(window.devicePixelRatio || 1, 2);
      canvas.width = Math.round(width * pixelRatio);
      canvas.height = Math.round(height * pixelRatio);
      context.setTransform(pixelRatio, 0, 0, pixelRatio, 0, 0);

      const nodeCount = Math.max(28, Math.round(width / 12));
      const initialSurface = height * (1 - clamp(percentRef.current, 0, 100) / 100);
      nodes = Array.from({ length: nodeCount }, (_, index) => ({
        y: initialSurface,
        velocity: 0,
        phase: index * 0.42,
      }));

      const columnCount = Math.max(24, Math.round(width / 11));
      const fontSize = Math.max(10, Math.min(14, width / 30));
      columns = Array.from({ length: columnCount }, (_, index) => {
        const seed = index * 997 + Math.round(width * 3);
        const random = seeded(seed);
        return {
          x: (index + 0.5) * (width / columnCount),
          offset: -random() * height * 0.6,
          speed: 260 + random() * 420,
          phase: random() * Math.PI * 2,
          fontSize,
          glyphs: Array.from({ length: 84 }, () => GLYPH_SET[Math.floor(random() * GLYPH_SET.length)]),
        };
      });
    };

    const resizeObserver = new ResizeObserver(resize);
    resizeObserver.observe(canvas);
    resize();

    const draw = (time: number) => {
      const delta = Math.min(0.034, (time - (lastTime || time)) / 1000 || 0.016);
      lastTime = time;
      const isReduced = reduceMotionRef.current;
      const movementDelta = isReduced ? 0 : delta;
      displayedPercent += (percentRef.current - displayedPercent) * (isReduced ? 0.25 : 0.075);

      const baseSurface = height * (1 - clamp(displayedPercent, 0, 100) / 100);
      const sensor = motion.current.sensorActive ? motion.current : motion.current;
      const tiltX = motion.current.sensorActive ? motion.current.sensorX : motion.current.pointerX;
      const tiltY = motion.current.sensorActive ? motion.current.sensorY : motion.current.pointerY;

      context.clearRect(0, 0, width, height);
      context.fillStyle = "#010402";
      context.fillRect(0, 0, width, height);

      const nodeCount = Math.max(1, nodes.length - 1);
      nodes.forEach((node, index) => {
        const xRatio = index / nodeCount;
        const ambient = isReduced
          ? 0
          : Math.sin(time * 0.00135 + node.phase) * 3.4 + Math.sin(time * 0.00056 + node.phase * 0.7) * 2.0;
        const slope = tiltX * (xRatio - 0.5) * width * 0.115;
        const push = tiltY * 8;
        const target = baseSurface + ambient + slope + push;
        const spring = (target - node.y) * 22;
        node.velocity += spring * movementDelta;
        node.velocity *= Math.exp(-5.5 * movementDelta);
        node.y += node.velocity * movementDelta;
      });

      const surfacePath = buildSurfacePath(context, nodes, width, height, baseSurface);
      context.save();
      context.clip(surfacePath);
      drawMatrixField(context, columns, time, delta, baseSurface, height, isReduced);
      context.restore();

      drawSurface(context, nodes, width, height, baseSurface, sensor.sensorActive, isReduced);

      frame = window.requestAnimationFrame(draw);
    };

    frame = window.requestAnimationFrame(draw);
    return () => {
      window.cancelAnimationFrame(frame);
      resizeObserver.disconnect();
    };
  }, [motion]);

  return (
    <canvas
      ref={canvasRef}
      className="matrix-canvas"
      aria-hidden="true"
      data-scroll-drag="ignore"
    />
  );
}

type SurfaceNode = {
  y: number;
  velocity: number;
  phase: number;
};

type MatrixColumn = {
  x: number;
  offset: number;
  speed: number;
  phase: number;
  fontSize: number;
  glyphs: string[];
};

function buildSurfacePath(
  context: CanvasRenderingContext2D,
  nodes: SurfaceNode[],
  width: number,
  height: number,
  fallback: number,
) {
  const path = new Path2D();
  if (nodes.length === 0) {
    path.rect(0, fallback, width, height - fallback);
    return path;
  }

  path.moveTo(0, nodes[0].y || fallback);
  nodes.forEach((node, index) => {
    const x = (index / Math.max(1, nodes.length - 1)) * width;
    path.lineTo(x, node.y || fallback);
  });
  path.lineTo(width, height);
  path.lineTo(0, height);
  path.closePath();
  return path;
}

function drawMatrixField(
    context: CanvasRenderingContext2D,
    columns: MatrixColumn[],
    time: number,
    delta: number,
  surface: number,
  height: number,
  reduceMotion: boolean,
) {
  const fontSize = columns[0]?.fontSize ?? 12;
  context.font = `${fontSize}px SFMono-Regular, Menlo, Consolas, monospace`;
  context.textBaseline = "top";

  columns.forEach((column, columnIndex) => {
    if (!reduceMotion) {
      column.offset += column.speed * delta;
      if (column.offset > height - surface + fontSize * 4) {
        column.offset = -fontSize * (10 + (columnIndex % 13));
      }
    }

    const rows = Math.ceil((height - surface) / (fontSize * 1.3)) + 8;
    for (let row = 0; row < rows; row += 1) {
      const y = surface + column.offset + row * fontSize * 1.3;
      if (y < surface - fontSize || y > height + fontSize) continue;

      const distance = Math.max(0, (y - surface) / Math.max(1, height - surface));
      const trail = 0.78 - distance * 0.52;
      const flicker = 0.84 + Math.sin(time * 0.004 + column.phase + row) * 0.16;
      const isLead = !reduceMotion && (Math.floor(time / 100) + columnIndex * 3) % Math.max(7, rows) === row;
      const alpha = clamp(trail * flicker * (isLead ? 1.5 : 1), 0.08, 0.98);
      context.fillStyle = isLead
        ? `rgba(168, 255, 172, ${alpha})`
        : `rgba(59, 255, 92, ${alpha})`;
      const glyph = column.glyphs[(row + Math.floor(time / 48)) % column.glyphs.length];
      context.fillText(glyph, column.x, y);
    }

    context.fillStyle = "rgba(0, 8, 2, 0.13)";
    context.fillRect(column.x - fontSize * 0.26, surface, fontSize * 0.52, height - surface);
  });
}

function drawSurface(
  context: CanvasRenderingContext2D,
  nodes: SurfaceNode[],
  width: number,
  height: number,
  fallback: number,
  sensorActive: boolean,
  reduceMotion: boolean,
) {
  const path = new Path2D();
  if (nodes.length === 0) {
    path.moveTo(0, fallback);
    path.lineTo(width, fallback);
  } else {
    path.moveTo(0, nodes[0].y || fallback);
    nodes.forEach((node, index) => {
      path.lineTo((index / Math.max(1, nodes.length - 1)) * width, node.y || fallback);
    });
  }

  const pulse = reduceMotion ? 0.7 : 0.74 + Math.sin(performance.now() * 0.002) * 0.08;
  context.save();
  context.lineCap = "round";
  context.lineJoin = "round";
  context.shadowColor = `rgba(81, 255, 104, ${sensorActive ? 0.82 : 0.66})`;
  context.shadowBlur = sensorActive ? 22 : 16;
  context.strokeStyle = `rgba(104, 255, 124, ${pulse})`;
  context.lineWidth = 2.2;
  context.stroke(path);
  context.shadowBlur = 0;
  context.strokeStyle = "rgba(206, 255, 206, 0.76)";
  context.lineWidth = 0.65;
  context.stroke(path);

  if (!reduceMotion) {
    context.strokeStyle = "rgba(65, 255, 91, 0.24)";
    context.lineWidth = 7;
    context.stroke(path);
  }
  context.restore();

  context.fillStyle = "rgba(91, 255, 113, 0.08)";
  context.fillRect(0, Math.max(0, fallback - 1), width, Math.min(10, height - fallback));
}

function seeded(seed: number) {
  let value = Math.abs(seed) + 1;
  return () => {
    value = (value * 1664525 + 1013904223) % 4294967296;
    return value / 4294967296;
  };
}

function clamp(value: number, min: number, max: number) {
  return Math.min(max, Math.max(min, value));
}
