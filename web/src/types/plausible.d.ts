interface PlausibleEventOptions {
  props?: Record<string, string | number | boolean | null | undefined>;
}

interface Window {
  plausible?: (eventName: string, options?: PlausibleEventOptions) => void;
}
