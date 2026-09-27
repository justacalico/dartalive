import 'package:flutter/services.dart';

/// Command ids + default bindings. Bindings are stored as a compact string:
/// "ctrl+shift+k", "space", "i". Order: ctrl, alt, shift, meta, key.
class Commands {
  static const playPause = 'playPause';
  static const playBackward = 'playBackward';
  static const playForward = 'playForward';
  static const stop = 'stop';
  static const frameBack = 'frameBack';
  static const frameFwd = 'frameFwd';
  static const goStart = 'goStart';
  static const goEnd = 'goEnd';
  static const prevEdit = 'prevEdit';
  static const nextEdit = 'nextEdit';
  static const setIn = 'setIn';
  static const setOut = 'setOut';
  static const clearInOut = 'clearInOut';
  static const markClip = 'markClip';
  static const addMarker = 'addMarker';
  static const cut = 'cut';
  static const delete = 'delete';
  static const rippleDelete = 'rippleDelete';
  static const undo = 'undo';
  static const redo = 'redo';
  static const save = 'save';
  static const saveAs = 'saveAs';
  static const openProject = 'openProject';
  static const newProject = 'newProject';
  static const newSequence = 'newSequence';
  static const importMedia = 'importMedia';
  static const export = 'export';
  static const zoomIn = 'zoomIn';
  static const zoomOut = 'zoomOut';
  static const zoomFit = 'zoomFit';
  static const toolSelect = 'toolSelect';
  static const toolRazor = 'toolRazor';
  static const toolRipple = 'toolRipple';
  static const toolSlip = 'toolSlip';
  static const toolSlide = 'toolSlide';
  static const selectAll = 'selectAll';
  static const deselect = 'deselect';
  static const duplicate = 'duplicate';
  static const copyClip = 'copyClip';
  static const pasteClip = 'pasteClip';
  static const linkToggle = 'linkToggle';
  static const addTransition = 'addTransition';
  static const muteTrack = 'muteTrack';
  static const lift = 'lift';
  static const extract = 'extract';
  static const toggleFullscreen = 'toggleFullscreen';
  static const renderZone = 'renderZone';
  static const findMedia = 'findMedia';

  static final names = <String, String>{
    playPause: 'Play / Pause',
    playBackward: 'Play backward',
    playForward: 'Play forward',
    stop: 'Stop',
    frameBack: 'Previous frame',
    frameFwd: 'Next frame',
    goStart: 'Go to start',
    goEnd: 'Go to end',
    prevEdit: 'Previous edit point',
    nextEdit: 'Next edit point',
    setIn: 'Set in-point',
    setOut: 'Set out-point',
    clearInOut: 'Clear in/out',
    markClip: 'Mark clip under playhead',
    addMarker: 'Add marker',
    cut: 'Cut at playhead',
    delete: 'Delete selection',
    rippleDelete: 'Ripple delete selection',
    undo: 'Undo',
    redo: 'Redo',
    save: 'Save project',
    saveAs: 'Save project as',
    openProject: 'Open project',
    newProject: 'New project',
    newSequence: 'New sequence',
    importMedia: 'Import media',
    export: 'Export',
    zoomIn: 'Timeline zoom in',
    zoomOut: 'Timeline zoom out',
    zoomFit: 'Zoom to fit',
    toolSelect: 'Selection tool',
    toolRazor: 'Razor tool',
    toolRipple: 'Ripple trim tool',
    toolSlip: 'Slip tool',
    toolSlide: 'Slide tool',
    selectAll: 'Select all clips',
    deselect: 'Deselect',
    duplicate: 'Duplicate clip',
    copyClip: 'Copy clip',
    pasteClip: 'Paste clip',
    linkToggle: 'Toggle clip link',
    addTransition: 'Apply default transition',
    muteTrack: 'Mute/unmute active track',
    lift: 'Lift in/out region',
    extract: 'Extract in/out region',
    toggleFullscreen: 'Fullscreen preview',
    renderZone: 'Render timeline zone',
    findMedia: 'Relocate missing media',
  };

  static final defaults = <String, String>{
    playPause: 'space',
    playBackward: 'j',
    playForward: 'l',
    stop: 'k',
    frameBack: 'left',
    frameFwd: 'right',
    goStart: 'home',
    goEnd: 'end',
    prevEdit: 'up',
    nextEdit: 'down',
    setIn: 'i',
    setOut: 'o',
    clearInOut: 'alt+x',
    markClip: 'x',
    addMarker: 'm',
    cut: 'ctrl+b',
    delete: 'delete',
    rippleDelete: 'shift+delete',
    undo: 'ctrl+z',
    redo: 'ctrl+shift+z',
    save: 'ctrl+s',
    saveAs: 'ctrl+shift+s',
    openProject: 'ctrl+o',
    newProject: 'ctrl+n',
    newSequence: 'ctrl+shift+n',
    importMedia: 'ctrl+i',
    export: 'ctrl+m',
    zoomIn: 'equal',
    zoomOut: 'minus',
    zoomFit: 'shift+z',
    toolSelect: 'v',
    toolRazor: 'c',
    toolRipple: 'r',
    toolSlip: 'y',
    toolSlide: 'u',
    selectAll: 'ctrl+a',
    deselect: 'escape',
    duplicate: 'ctrl+d',
    copyClip: 'ctrl+c',
    pasteClip: 'ctrl+v',
    linkToggle: 'ctrl+l',
    addTransition: 'ctrl+t',
    lift: ';',
    extract: "'",
    toggleFullscreen: 'ctrl+shift+f',
    renderZone: 'ctrl+r',
    findMedia: 'ctrl+shift+r',
  };
}

/// String -> LogicalKeyboardKey combos and back.
class KeyCombo {
  final bool ctrl, alt, shift, meta;
  final String key;
  const KeyCombo(this.key,
      {this.ctrl = false, this.alt = false, this.shift = false, this.meta = false});

  static KeyCombo? parse(String s) {
    if (s.isEmpty) return null;
    final parts = s.toLowerCase().split('+');
    final key = parts.last;
    return KeyCombo(
      key,
      ctrl: parts.contains('ctrl'),
      alt: parts.contains('alt'),
      shift: parts.contains('shift'),
      meta: parts.contains('meta'),
    );
  }

  static KeyCombo? fromEvent(KeyEvent e) {
    if (e is! KeyDownEvent) return null;
    final k = e.logicalKey;
    // ignore pure modifier presses
    if (k == LogicalKeyboardKey.controlLeft ||
        k == LogicalKeyboardKey.controlRight ||
        k == LogicalKeyboardKey.shiftLeft ||
        k == LogicalKeyboardKey.shiftRight ||
        k == LogicalKeyboardKey.altLeft ||
        k == LogicalKeyboardKey.altRight ||
        k == LogicalKeyboardKey.metaLeft ||
        k == LogicalKeyboardKey.metaRight) {
      return null;
    }
    final name = _keyName(k);
    if (name == null) return null;
    return KeyCombo(
      name,
      ctrl: HardwareKeyboard.instance.isControlPressed,
      alt: HardwareKeyboard.instance.isAltPressed,
      shift: HardwareKeyboard.instance.isShiftPressed,
      meta: HardwareKeyboard.instance.isMetaPressed,
    );
  }

  static String? _keyName(LogicalKeyboardKey k) {
    if (k == LogicalKeyboardKey.space) return 'space';
    if (k == LogicalKeyboardKey.arrowLeft) return 'left';
    if (k == LogicalKeyboardKey.arrowRight) return 'right';
    if (k == LogicalKeyboardKey.arrowUp) return 'up';
    if (k == LogicalKeyboardKey.arrowDown) return 'down';
    if (k == LogicalKeyboardKey.home) return 'home';
    if (k == LogicalKeyboardKey.end) return 'end';
    if (k == LogicalKeyboardKey.delete) return 'delete';
    if (k == LogicalKeyboardKey.backspace) return 'backspace';
    if (k == LogicalKeyboardKey.enter) return 'enter';
    if (k == LogicalKeyboardKey.escape) return 'escape';
    if (k == LogicalKeyboardKey.tab) return 'tab';
    if (k == LogicalKeyboardKey.equal) return 'equal';
    if (k == LogicalKeyboardKey.minus) return 'minus';
    if (k == LogicalKeyboardKey.comma) return 'comma';
    if (k == LogicalKeyboardKey.period) return 'period';
    if (k == LogicalKeyboardKey.slash) return 'slash';
    if (k == LogicalKeyboardKey.semicolon) return 'semicolon';
    if (k == LogicalKeyboardKey.quote) return "'";
    if (k == LogicalKeyboardKey.backslash) return 'backslash';
    if (k == LogicalKeyboardKey.bracketLeft) return '[';
    if (k == LogicalKeyboardKey.bracketRight) return ']';
    final label = k.keyLabel.toLowerCase();
    if (label.length == 1) return label;
    final m = RegExp(r'^f(\d+)$').firstMatch(label);
    if (m != null) return label;
    return null;
  }

  String encode() =>
      '${ctrl ? 'ctrl+' : ''}${alt ? 'alt+' : ''}${shift ? 'shift+' : ''}${meta ? 'meta+' : ''}$key';

  bool matches(KeyCombo o) =>
      key == o.key &&
      ctrl == o.ctrl &&
      alt == o.alt &&
      shift == o.shift &&
      meta == o.meta;

  @override
  String toString() => encode().replaceAll('space', 'Space');
}

class ShortcutMap {
  final Map<String, String> map; // command -> combo
  ShortcutMap(Map<String, String>? overrides)
      : map = {...Commands.defaults, ...?overrides};

  String? commandFor(KeyCombo c) {
    for (final e in map.entries) {
      final p = KeyCombo.parse(e.value);
      if (p != null && p.matches(c)) return e.key;
    }
    return null;
  }

  String combo(String command) =>
      map[command] ?? Commands.defaults[command] ?? '';
}
