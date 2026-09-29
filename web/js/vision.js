// MediaPipe face detection and person segmentation, running in the browser (WebAssembly).
// The photo is never uploaded; only the library and the two small models are downloaded.

const VERSION = '1.0.1';
const LIB = `https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@${VERSION}`;
const MODELS = 'https://storage.googleapis.com/mediapipe-models';
const FACE_MODEL = `${MODELS}/face_detector/blaze_face_short_range/float16/latest/blaze_face_short_range.tflite`;
const PERSON_MODEL = `${MODELS}/image_segmenter/selfie_segmenter/float16/latest/selfie_segmenter.tflite`;

let models;

export function loadModels() {
  models ??= (async () => {
    const { FilesetResolver, FaceDetector, ImageSegmenter } = await import(`${LIB}/vision_bundle.mjs`);
    const fileset = await FilesetResolver.forVisionTasks(`${LIB}/wasm`);
    const [face, person] = await Promise.all([
      FaceDetector.createFromOptions(fileset, {
        baseOptions: { modelAssetPath: FACE_MODEL, delegate: 'CPU' },
        runningMode: 'IMAGE',
        minDetectionConfidence: 0.5,
      }),
      ImageSegmenter.createFromOptions(fileset, {
        baseOptions: { modelAssetPath: PERSON_MODEL, delegate: 'CPU' },
        runningMode: 'IMAGE',
        outputConfidenceMasks: true,
        outputCategoryMask: false,
      }),
    ]);
    return { face, person };
  })();
  models.catch(() => { models = undefined; }); // allow a retry after a network failure
  return models;
}

/**
 * @param {HTMLCanvasElement} canvas the photo (any size; coordinates are returned in its pixels)
 * @returns {Promise<{face: {x,y,width,height}|null, mask: {data: Float32Array, width, height}|null}>}
 */
export async function analyze(canvas) {
  const { face, person } = await loadModels();

  // Short-range model works best on a moderately sized input.
  const scale = Math.min(1, 1024 / Math.max(canvas.width, canvas.height));
  const small = document.createElement('canvas');
  small.width = Math.round(canvas.width * scale);
  small.height = Math.round(canvas.height * scale);
  small.getContext('2d').drawImage(canvas, 0, 0, small.width, small.height);

  let bestFace = null;
  for (const d of face.detect(small).detections) {
    const b = d.boundingBox;
    if (b && (!bestFace || b.width * b.height > bestFace.width * bestFace.height)) {
      bestFace = { x: b.originX / scale, y: b.originY / scale, width: b.width / scale, height: b.height / scale };
    }
  }

  let mask = null;
  const result = person.segment(small);
  const m = result.confidenceMasks?.[0];
  if (m) mask = { data: Float32Array.from(m.getAsFloat32Array()), width: m.width, height: m.height };
  result.close();

  return { face: bestFace, mask };
}
