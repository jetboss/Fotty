/** Request picture-in-picture on the first video inside a player stage. */
export async function requestWatchPictureInPicture(stage: HTMLElement | null) {
  if (!stage) return { ok: false as const, reason: "no-stage" };

  const video = stage.querySelector("video");
  if (video && document.pictureInPictureEnabled && !video.disablePictureInPicture) {
    try {
      if (document.pictureInPictureElement === video) {
        await document.exitPictureInPicture();
        return { ok: true as const, mode: "video-exit" as const };
      }
      await video.requestPictureInPicture();
      return { ok: true as const, mode: "video" as const };
    } catch {
      return { ok: false as const, reason: "video-blocked" };
    }
  }

  return { ok: false as const, reason: "embed-only" };
}

export function canAttemptWatchPiP(stage: HTMLElement | null) {
  return Boolean(stage?.querySelector("video") && document.pictureInPictureEnabled);
}
