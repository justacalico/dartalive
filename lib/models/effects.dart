import 'model.dart';

/// Effect catalog. Each effect knows how to emit ffmpeg filter snippets.
/// Params flagged `expr` can be evaluated per-frame by ffmpeg, so their
/// keyframes become expressions; anything else forces clip segmentation at
/// keyframe boundaries.

enum ParamType { number, toggle, choice, color, text, file }

class ParamDef {
  final String id;
  final String name;
  final ParamType type;
  final double min, max, def;
  final double step;
  final List<String> options;
  final bool expr; // supports per-frame expression evaluation
  final String unit;
  const ParamDef(this.id, this.name,
      {this.type = ParamType.number,
      this.min = 0,
      this.max = 1,
      this.def = 0,
      this.step = 0.01,
      this.options = const [],
      this.expr = false,
      this.unit = ''});
}

class EffectDef {
  final String id;
  final String name;
  final String category;
  final bool audio;
  final List<ParamDef> params;
  final String description;
  const EffectDef(this.id, this.name, this.category,
      {this.audio = false, this.params = const [], this.description = ''});

  Map<String, dynamic> defaults() =>
      {for (final p in params) p.id: p.type == ParamType.number ? p.def : (p.type == ParamType.toggle ? false : (p.type == ParamType.choice ? (p.options.isEmpty ? '' : p.options.first) : ''))};

  /// True when a keyframed param can't be expressed per-frame and the clip
  /// must be split at keyframe boundaries.
  bool needsSegments(ClipEffect fx) {
    for (final e in fx.keyframes.entries) {
      if (e.value.length < 2) continue;
      final p = params.where((x) => x.id == e.key).firstOrNull;
      if (p != null && !p.expr) return true;
    }
    return false;
  }
}

class Effects {
  static const cats = {
    'Transform': 'transform',
    'Color': 'color',
    'Blur & Sharpen': 'blur',
    'Stylize': 'stylize',
    'Keying': 'keying',
    'Text': 'text',
    'Audio': 'audio',
  };

  static final List<EffectDef> all = [
    // ---------------- video ----------------
    const EffectDef('transform', 'Transform', 'transform', params: [
      ParamDef('x', 'Position X', min: -1, max: 1, def: 0, expr: true),
      ParamDef('y', 'Position Y', min: -1, max: 1, def: 0, expr: true),
      ParamDef('sx', 'Scale X', min: 0, max: 8, def: 1, expr: true),
      ParamDef('sy', 'Scale Y', min: 0, max: 8, def: 1, expr: true),
      ParamDef('rot', 'Rotation', min: -360, max: 360, def: 0, expr: true, unit: '°'),
      ParamDef('op', 'Opacity', min: 0, max: 1, def: 1, expr: true),
      ParamDef('anchorX', 'Anchor X', min: 0, max: 1, def: 0.5),
      ParamDef('anchorY', 'Anchor Y', min: 0, max: 1, def: 0.5),
    ]),
    const EffectDef('crop', 'Crop', 'transform', params: [
      ParamDef('l', 'Left', min: 0, max: 1, def: 0),
      ParamDef('r', 'Right', min: 0, max: 1, def: 0),
      ParamDef('t', 'Top', min: 0, max: 1, def: 0),
      ParamDef('b', 'Bottom', min: 0, max: 1, def: 0),
    ]),
    const EffectDef('opacity', 'Opacity', 'transform', params: [
      ParamDef('op', 'Opacity', min: 0, max: 1, def: 1, expr: false),
    ]),
    const EffectDef('eq', 'Brightness / Contrast', 'color', params: [
      ParamDef('brightness', 'Brightness', min: -1, max: 1, def: 0),
      ParamDef('contrast', 'Contrast', min: 0, max: 3, def: 1),
      ParamDef('saturation', 'Saturation', min: 0, max: 3, def: 1),
      ParamDef('gamma', 'Gamma', min: 0.1, max: 10, def: 1),
      ParamDef('gamma_r', 'Gamma R', min: 0.1, max: 10, def: 1),
      ParamDef('gamma_g', 'Gamma G', min: 0.1, max: 10, def: 1),
      ParamDef('gamma_b', 'Gamma B', min: 0.1, max: 10, def: 1),
    ]),
    const EffectDef('levels', 'Levels', 'color', params: [
      ParamDef('rimin', 'Black In', min: 0, max: 1, def: 0),
      ParamDef('rimax', 'White In', min: 0, max: 1, def: 1),
      ParamDef('gammaval', 'Gamma', min: 0.1, max: 10, def: 1),
      ParamDef('romin', 'Black Out', min: 0, max: 1, def: 0),
      ParamDef('romax', 'White Out', min: 0, max: 1, def: 1),
    ]),
    const EffectDef('colorbalance', 'Color Balance', 'color', params: [
      ParamDef('rs', 'Shadow R', min: -1, max: 1, def: 0),
      ParamDef('gs', 'Shadow G', min: -1, max: 1, def: 0),
      ParamDef('bs', 'Shadow B', min: -1, max: 1, def: 0),
      ParamDef('rm', 'Mid R', min: -1, max: 1, def: 0),
      ParamDef('gm', 'Mid G', min: -1, max: 1, def: 0),
      ParamDef('bm', 'Mid B', min: -1, max: 1, def: 0),
      ParamDef('rh', 'High R', min: -1, max: 1, def: 0),
      ParamDef('gh', 'High G', min: -1, max: 1, def: 0),
      ParamDef('bh', 'High B', min: -1, max: 1, def: 0),
    ]),
    const EffectDef('channelmixer', 'Channel Mixer', 'color', params: [
      ParamDef('rr', 'R→R', min: 0, max: 2, def: 1),
      ParamDef('rg', 'G→R', min: 0, max: 2, def: 0),
      ParamDef('rb', 'B→R', min: 0, max: 2, def: 0),
      ParamDef('gr', 'R→G', min: 0, max: 2, def: 0),
      ParamDef('gg', 'G→G', min: 0, max: 2, def: 1),
      ParamDef('gb', 'B→G', min: 0, max: 2, def: 0),
      ParamDef('br', 'R→B', min: 0, max: 2, def: 0),
      ParamDef('bg', 'G→B', min: 0, max: 2, def: 0),
      ParamDef('bb', 'B→B', min: 0, max: 2, def: 1),
    ]),
    const EffectDef('curves', 'Curves', 'color', params: [
      ParamDef('master', 'Master', type: ParamType.text),
      ParamDef('r', 'Red', type: ParamType.text),
      ParamDef('g', 'Green', type: ParamType.text),
      ParamDef('b', 'Blue', type: ParamType.text),
    ]),
    const EffectDef('hue', 'Hue / Saturation', 'color', params: [
      ParamDef('h', 'Hue', min: -180, max: 180, def: 0, unit: '°'),
      ParamDef('s', 'Saturation', min: 0, max: 5, def: 1),
      ParamDef('b', 'Brightness', min: -10, max: 10, def: 0),
    ]),
    const EffectDef('colorcorrect', 'Color Correct', 'color', params: [
      ParamDef('saturation', 'Saturation', min: -3, max: 3, def: 0),
      ParamDef('analyze', 'Analyze', type: ParamType.choice, options: ['manual', 'median', 'mean', 'minmax']),
    ]),
    const EffectDef('lut3d', 'LUT (3D)', 'color', params: [
      ParamDef('file', 'LUT file (.cube)', type: ParamType.file),
      ParamDef('interp', 'Interpolation', type: ParamType.choice, options: ['nearest', 'trilinear', 'tetrahedral']),
    ]),
    const EffectDef('blur', 'Gaussian Blur', 'blur', params: [
      ParamDef('sigma', 'Strength', min: 0, max: 100, def: 5),
      ParamDef('planes', 'Planes', type: ParamType.choice, options: ['all', 'luma']),
    ]),
    const EffectDef('boxblur', 'Box Blur', 'blur', params: [
      ParamDef('radius', 'Radius', min: 0, max: 50, def: 2),
      ParamDef('power', 'Power', min: 1, max: 10, def: 2),
    ]),
    const EffectDef('sharpen', 'Sharpen', 'blur', params: [
      ParamDef('amount', 'Amount', min: 0, max: 3, def: 1),
      ParamDef('size', 'Matrix size', type: ParamType.choice, options: ['5', '7', '9']),
    ]),
    const EffectDef('denoise', 'Denoise', 'blur', params: [
      ParamDef('luma', 'Luma strength', min: 0, max: 16, def: 4),
      ParamDef('chroma', 'Chroma strength', min: 0, max: 16, def: 3),
    ]),
    const EffectDef('vignette', 'Vignette', 'stylize', params: [
      ParamDef('angle', 'Angle', min: 0.2, max: 1.5, def: 0.8),
      ParamDef('mode', 'Mode', type: ParamType.choice, options: ['forward', 'backward']),
    ]),
    const EffectDef('hflip', 'Flip Horizontal', 'transform'),
    const EffectDef('vflip', 'Flip Vertical', 'transform'),
    const EffectDef('chromakey', 'Chroma Key', 'keying', params: [
      ParamDef('color', 'Key color', type: ParamType.color, def: 0),
      ParamDef('similarity', 'Similarity', min: 0, max: 1, def: 0.3),
      ParamDef('blend', 'Blend', min: 0, max: 1, def: 0.1),
      ParamDef('despill', 'Despill', type: ParamType.toggle),
    ]),
    const EffectDef('grayscale', 'Grayscale', 'stylize'),
    const EffectDef('sepia', 'Sepia', 'stylize', params: [
      ParamDef('mix', 'Mix', min: 0, max: 1, def: 1),
    ]),
    const EffectDef('invert', 'Invert', 'stylize', params: [
      ParamDef('alpha', 'Invert alpha too', type: ParamType.toggle),
    ]),
    const EffectDef('pixelate', 'Pixelate', 'stylize', params: [
      ParamDef('size', 'Pixel size', min: 2, max: 128, def: 16, step: 1),
    ]),
    const EffectDef('noise', 'Noise', 'stylize', params: [
      ParamDef('strength', 'Strength', min: 0, max: 100, def: 10),
      ParamDef('temporal', 'Temporal', type: ParamType.toggle, def: 1),
    ]),
    const EffectDef('deshake', 'Stabilize (deshake)', 'transform', params: [
      ParamDef('x', 'Search X', min: -1, max: 1, def: 0),
      ParamDef('y', 'Search Y', min: -1, max: 1, def: 0),
      ParamDef('w', 'Window', min: 4, max: 64, def: 16, step: 1),
      ParamDef('h', 'Window H', min: 4, max: 64, def: 16, step: 1),
    ]),
    const EffectDef('fadein', 'Fade In', 'transform', params: [
      ParamDef('d', 'Duration (frames)', min: 1, max: 300, def: 24, step: 1),
      ParamDef('color', 'Color', type: ParamType.choice, options: ['black', 'white']),
    ]),
    const EffectDef('fadeout', 'Fade Out', 'transform', params: [
      ParamDef('d', 'Duration (frames)', min: 1, max: 300, def: 24, step: 1),
      ParamDef('color', 'Color', type: ParamType.choice, options: ['black', 'white']),
    ]),
    const EffectDef('drawtext', 'Text', 'text', params: [
      ParamDef('text', 'Text', type: ParamType.text, def: 0),
      ParamDef('size', 'Size', min: 8, max: 500, def: 64, step: 1),
      ParamDef('color', 'Color', type: ParamType.color),
      ParamDef('x', 'X', min: -0.5, max: 1.5, def: 0.5, expr: true),
      ParamDef('y', 'Y', min: -0.5, max: 1.5, def: 0.5, expr: true),
      ParamDef('box', 'Background box', type: ParamType.toggle),
      ParamDef('boxcolor', 'Box color', type: ParamType.color, def: 0),
      ParamDef('font', 'Font', type: ParamType.text),
    ]),
    // ---------------- audio ----------------
    const EffectDef('gain', 'Gain', 'audio', audio: true, params: [
      ParamDef('v', 'Gain', min: -60, max: 60, def: 0, expr: true, unit: 'dB'),
    ]),
    const EffectDef('pan', 'Pan', 'audio', audio: true, params: [
      ParamDef('p', 'Pan', min: -1, max: 1, def: 0),
    ]),
    const EffectDef('afadein', 'Audio Fade In', 'audio', audio: true, params: [
      ParamDef('d', 'Duration (frames)', min: 1, max: 600, def: 24, step: 1),
    ]),
    const EffectDef('afadeout', 'Audio Fade Out', 'audio', audio: true, params: [
      ParamDef('d', 'Duration (frames)', min: 1, max: 600, def: 24, step: 1),
    ]),
    const EffectDef('aeq', 'EQ (3-band)', 'audio', audio: true, params: [
      ParamDef('low', 'Low', min: -30, max: 30, def: 0, unit: 'dB'),
      ParamDef('lowf', 'Low freq', min: 40, max: 500, def: 200, step: 1),
      ParamDef('mid', 'Mid', min: -30, max: 30, def: 0, unit: 'dB'),
      ParamDef('midf', 'Mid freq', min: 200, max: 5000, def: 1000, step: 1),
      ParamDef('high', 'High', min: -30, max: 30, def: 0, unit: 'dB'),
      ParamDef('highf', 'High freq', min: 2000, max: 18000, def: 6000, step: 1),
    ]),
    const EffectDef('acompressor', 'Compressor', 'audio', audio: true, params: [
      ParamDef('threshold', 'Threshold', min: 0, max: 1, def: 0.09),
      ParamDef('ratio', 'Ratio', min: 1, max: 20, def: 3),
      ParamDef('attack', 'Attack ms', min: 0.01, max: 2000, def: 20),
      ParamDef('release', 'Release ms', min: 0.01, max: 9000, def: 250),
      ParamDef('makeup', 'Makeup', min: 1, max: 64, def: 2),
    ]),
    const EffectDef('alimiter', 'Limiter', 'audio', audio: true, params: [
      ParamDef('limit', 'Limit', min: 0.01, max: 1, def: 0.9),
      ParamDef('attack', 'Attack ms', min: 0.1, max: 80, def: 5),
      ParamDef('release', 'Release ms', min: 1, max: 8000, def: 50),
    ]),
    const EffectDef('loudnorm', 'Loudness Normalize', 'audio', audio: true, params: [
      ParamDef('i', 'Integrated LUFS', min: -70, max: -5, def: -16),
      ParamDef('tp', 'True peak', min: -9, max: 0, def: -1.5),
      ParamDef('lra', 'LRA', min: 1, max: 50, def: 11),
    ]),
    const EffectDef('agate', 'Noise Gate', 'audio', audio: true, params: [
      ParamDef('threshold', 'Threshold', min: 0, max: 1, def: 0.02),
      ParamDef('ratio', 'Ratio', min: 1, max: 9000, def: 2),
      ParamDef('attack', 'Attack ms', min: 0.01, max: 9000, def: 20),
      ParamDef('release', 'Release ms', min: 0.01, max: 9000, def: 250),
    ]),
    const EffectDef('aecho', 'Echo', 'audio', audio: true, params: [
      ParamDef('delay', 'Delay ms', min: 1, max: 5000, def: 500),
      ParamDef('decay', 'Decay', min: 0, max: 1, def: 0.5),
    ]),
    const EffectDef('highpass', 'High Pass', 'audio', audio: true, params: [
      ParamDef('f', 'Frequency', min: 20, max: 4000, def: 200, step: 1),
    ]),
    const EffectDef('lowpass', 'Low Pass', 'audio', audio: true, params: [
      ParamDef('f', 'Frequency', min: 100, max: 20000, def: 3000, step: 1),
    ]),
  ];

  static EffectDef? byId(String id) {
    for (final e in all) {
      if (e.id == id) return e;
    }
    return null;
  }

  static List<EffectDef> get video =>
      all.where((e) => !e.audio).toList();
  static List<EffectDef> get audio => all.where((e) => e.audio).toList();
}
