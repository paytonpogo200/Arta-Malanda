export function clamp(value: number, min: number, max: number) {
  return Math.max(min, Math.min(max, value));
}

export function percent(current: number, max: number) {
  if (max <= 0) return 0;
  return clamp((current / max) * 100, 0, 100);
}

export function signed(value: number) {
  return value > 0 ? `+${value}` : String(value);
}
