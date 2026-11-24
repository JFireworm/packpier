const MAIN_SURFACE = '[data-app-shell-main-surface="default"]';
const TIMELINE = "[data-app-action-timeline-scroll]";
const TRANSCRIPT = '[class~="[container-name:thread-content]"]';
const HEADER = '[aria-hidden="true"][class~="pointer-events-none"][class*="bg-[image:var(--app-shell-content-fade,"]';
const FOOTER = '[data-thread-scroll-footer="true"]';
const MARKER = "data-packpier-cbgp-transcript-clip";
const CLIP_PROPERTY = "--ct-cbgp-transcript-clip";

export const THREAD_CLIP_ANCHORS = [TIMELINE, TRANSCRIPT, HEADER, FOOTER].join(", ");

export function createThreadClipping() {
  let layout = null;
  let lastClip = "";
  const resizeObserver = new ResizeObserver(update);

  function update() {
    if (!layout) return;
    const { timeline, transcript, header, footer } = layout;
    const viewport = timeline.getBoundingClientRect();
    const content = transcript.getBoundingClientRect();
    const top = Math.max(viewport.top, header.getBoundingClientRect().bottom);
    const bottom = Math.min(viewport.bottom, footer.getBoundingClientRect().top);
    // The title bar and composer stay in place while the transcript's own box scrolls.
    const clip = `inset(${Math.max(0, top - content.top)}px 0 ${Math.max(0, content.bottom - bottom)}px)`;
    if (clip !== lastClip) {
      transcript.style.setProperty(CLIP_PROPERTY, clip);
      lastClip = clip;
    }
  }

  function clear() {
    if (!layout) return;
    resizeObserver.disconnect();
    layout.timeline.removeEventListener("scroll", update);
    layout.transcript.removeAttribute(MARKER);
    layout.transcript.style.removeProperty(CLIP_PROPERTY);
    layout = null;
    lastClip = "";
  }

  function sync(root) {
    const timelines = root?.querySelectorAll(`${MAIN_SURFACE} ${TIMELINE}`) ?? [];
    const timeline = Array.from(timelines).find(node => node.clientHeight > 0);
    const transcript = timeline?.querySelector(`:scope > ${TRANSCRIPT}`);
    const header = timeline?.closest(MAIN_SURFACE)?.querySelector(HEADER);
    const footer = timeline?.querySelector(`:scope > [class~="absolute"][class~="pointer-events-none"]:has(> ${FOOTER})`);
    if (!transcript || !header || !footer) {
      clear();
      return;
    }
    if (!layout || layout.timeline !== timeline || layout.transcript !== transcript ||
        layout.header !== header || layout.footer !== footer) {
      clear();
      layout = { timeline, transcript, header, footer };
      transcript.setAttribute(MARKER, "");
      timeline.addEventListener("scroll", update, { passive: true });
      for (const node of Object.values(layout)) resizeObserver.observe(node);
    }
    update();
  }

  return { sync, clear };
}
