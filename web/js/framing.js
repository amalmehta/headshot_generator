// Head-and-shoulders framing. Pure geometry, canvas coordinates (origin top-left), pixels.
// Mirrors Sources/HeadshotCore/Framing.swift.

export const CROPS = {
  square: { label: 'Square 1:1', ratio: 1 },
  portrait: { label: 'Portrait 4:5', ratio: 0.8 },
  original: { label: 'Uncropped', ratio: null },
};

const FACE_HEIGHT_SHARE = 0.40;   // share of frame height the face box fills
const FACE_CENTER_FROM_TOP = 0.44; // where the face centre sits, from the top of the frame

/**
 * @param {{x:number,y:number,width:number,height:number}|null} face
 * @param {{width:number,height:number}} image
 * @param {keyof CROPS} aspect
 */
export function cropRect(face, image, aspect) {
  const ratio = CROPS[aspect].ratio;
  if (ratio == null) return { x: 0, y: 0, width: image.width, height: image.height };
  if (!face) return centered(ratio, image);

  let height = face.height / FACE_HEIGHT_SHARE;
  let width = height * ratio;
  if (width > image.width) { width = image.width; height = width / ratio; }
  if (height > image.height) { height = image.height; width = height * ratio; }

  const cx = face.x + face.width / 2;
  const cy = face.y + face.height / 2;
  let x = cx - width / 2;
  let y = cy - height * FACE_CENTER_FROM_TOP;
  x = Math.min(Math.max(x, 0), image.width - width);
  y = Math.min(Math.max(y, 0), image.height - height);
  return { x: Math.round(x), y: Math.round(y), width: Math.round(width), height: Math.round(height) };
}

function centered(ratio, image) {
  let width = image.width;
  let height = width / ratio;
  if (height > image.height) { height = image.height; width = height * ratio; }
  return {
    x: Math.round((image.width - width) / 2), y: Math.round((image.height - height) / 2),
    width: Math.round(width), height: Math.round(height),
  };
}
