//! sailor — Zig TUI framework & CLI toolkit
//!
//! Composable modules for building interactive terminal applications.
//! Each module is independently usable.
//!
//! ## Modules
//!
//! - `term`     — Terminal backend (raw mode, key reading, TTY detection)
//! - `color`    — Styled output (ANSI codes, 256/truecolor, NO_COLOR)
//! - `arg`      — Argument parser (flags, subcommands, help generation)
//! - `repl`     — Interactive REPL (line editing, history, completion)
//! - `progress` — Progress indicators (bar, spinner, multi-progress)
//! - `fmt`      — Result formatting (table, JSON, CSV)
//! - `tui`      — Full-screen TUI framework (layout, widgets, double buffering)

const std = @import("std");
const builtin = @import("builtin");

// Phase 1 modules (v0.1.0)
pub const term = @import("term.zig");
pub const color = @import("color.zig");
pub const arg = @import("arg.zig");
pub const env = @import("env.zig");

// Phase 2 modules (v0.2.0)
pub const repl = @import("repl.zig");
pub const progress = @import("progress.zig");
pub const fmt = @import("fmt.zig");

// Phase 3+ modules (v0.3.0+)
pub const tui = @import("tui/tui.zig");

// Phase 6 modules (v1.0.0)
pub const bench = @import("bench.zig");

// Post-v1.0 modules (v1.1.0 — Accessibility & Internationalization)
pub const accessibility = @import("accessibility.zig");
pub const focus = @import("focus.zig");
pub const keybindings = @import("keybindings.zig");
pub const unicode = @import("unicode.zig");
pub const bidi = @import("bidi.zig");

// v2.5.0 — iTerm2 Protocol & Unicode Grapheme Support
pub const grapheme = @import("grapheme.zig");
pub const quirks = @import("tui/quirks.zig");

// v1.4.0 — Memory Management
pub const pool = @import("pool.zig");

// v1.5.0 — State Management & Testing
pub const eventbus = @import("eventbus.zig");
pub const command = @import("command.zig");

// v1.14.0 — Performance & Memory Optimization
pub const profiler = @import("profiler.zig");

// v1.16.0 — Terminal Capability Database
pub const termcap = @import("termcap.zig");

// v1.18.0 — Developer Experience & Tooling
pub const ThemeWatcher = @import("tui/hotreload.zig").ThemeWatcher;
pub const WidgetInspector = @import("tui/inspector.zig").WidgetInspector;
pub const WidgetNode = @import("tui/inspector.zig").WidgetNode;
pub const docgen = @import("docgen.zig");

// v1.20.0 — Quality & Completeness
pub const error_context = @import("error_context.zig");

// v1.30.0 — Error Handling & Debugging Enhancements
pub const debug_log = @import("debug_log.zig");
pub const stack_trace = @import("stack_trace.zig");

// v1.34.0 — Terminal Clipboard & System Integration
pub const clipboard = @import("clipboard.zig");
pub const terminal_detect = @import("terminal_detect.zig");
pub const terminal_caps = @import("terminal_caps.zig");
pub const paste = @import("paste.zig");

// v1.35.0 — Widget Accessibility & Keyboard Navigation
pub const aria = @import("aria.zig");
pub const focus_trap = @import("focus_trap.zig");

// v1.36.0 — Widget Performance Metrics
pub const render_metrics = @import("render_metrics.zig");
pub const memory_metrics = @import("memory_metrics.zig");
pub const event_metrics = @import("event_metrics.zig");

// v1.37.0 — v2.0.0 Deprecation Warnings & Bridge APIs
pub const deprecation = @import("deprecation.zig");

// v1.23.0 — Plugin Architecture & Extensibility
pub const ThemeLoader = @import("tui/theme_loader.zig").ThemeLoader;

// v2.3.0 — Advanced Widget Features (State Persistence)
pub const widget_state = @import("tui/widget_state.zig");

// v1.24.0 — Animation & Transitions
pub const animation = @import("tui/animation.zig");
pub const transition = @import("tui/transition.zig");

// v2.4.0 — Testing utilities
pub const testing = @import("testing.zig");

// v2.6.0 — Input Validation Framework
pub const validation = @import("validation.zig");

// v2.8.0 — Event System & Async Integration
pub const taskrunner = @import("taskrunner.zig");

// v2.9.0 — Error Recovery & Resilience
pub const ErrorBoundary = @import("tui/error_recovery.zig").ErrorBoundary;
pub const StateRecovery = @import("tui/error_recovery.zig").StateRecovery;
pub const ErrorReporter = @import("tui/error_recovery.zig").ErrorReporter;
pub const GracefulDegradation = @import("tui/error_recovery.zig").GracefulDegradation;
pub const ErrorInjector = @import("tui/error_recovery.zig").ErrorInjector;

pub const DeveloperConsole = @import("developer_console.zig").DeveloperConsole;
pub const WidgetInfo = @import("developer_console.zig").WidgetInfo;
pub const Recording = @import("developer_console.zig").Recording;
pub const Keypress = @import("developer_console.zig").Keypress;
pub const ExportFormat = @import("developer_console.zig").ExportFormat;

// v2.10.0 — LLM Integration Layer
pub const LlmClient = @import("llm_client.zig").LlmClient;
pub const TokenBudget = @import("llm_client.zig").TokenBudget;
pub const RateLimiter = @import("llm_client.zig").RateLimiter;
pub const PromptTemplate = @import("llm_client.zig").PromptTemplate;
pub const ResponseStreamWidget = @import("llm_client.zig").ResponseStreamWidget;

// v2.10.0 — Smart Autocomplete
pub const smart_autocomplete = @import("smart_autocomplete.zig");
pub const CompletionContext = smart_autocomplete.CompletionContext;
pub const Suggestion = smart_autocomplete.Suggestion;
pub const LocalSource = smart_autocomplete.LocalSource;
pub const LlmSource = smart_autocomplete.LlmSource;
pub const PatternSource = smart_autocomplete.PatternSource;
pub const SmartAutocomplete = smart_autocomplete.SmartAutocomplete;
pub const CompletionMode = smart_autocomplete.CompletionMode;

// v2.10.0 — Layout Intelligence
pub const layout_intelligence = @import("layout_intelligence.zig");
pub const LayoutIssue = layout_intelligence.LayoutIssue;
pub const LayoutAnalyzer = layout_intelligence.LayoutAnalyzer;
pub const ResponsivenessChecker = layout_intelligence.ResponsivenessChecker;
pub const AccessibilityChecker = layout_intelligence.AccessibilityChecker;
pub const PerformanceAnalyzer = layout_intelligence.PerformanceAnalyzer;

// v2.10.0 — Natural Language Commands
pub const natural_language_commands = @import("natural_language_commands.zig");
pub const Intent = natural_language_commands.Intent;
pub const CommandParser = natural_language_commands.CommandParser;
pub const CommandHistory = natural_language_commands.CommandHistory;
pub const TutorialMode = natural_language_commands.TutorialMode;
pub const Context = natural_language_commands.Context;

// v2.11.0 — Extended Graphics & Protocol Support
pub const sixel = @import("tui/sixel.zig");
pub const SixelImage = sixel.SixelImage;
pub const SixelEncoder = sixel.SixelEncoder;
pub const SixelDecoder = sixel.SixelDecoder;
pub const SixelCompressor = sixel.SixelCompressor;
pub const SixelAnimator = sixel.SixelAnimator;
pub const ColorPalette = sixel.ColorPalette;
pub const QuantizationAlgorithm = sixel.QuantizationAlgorithm;
pub const DistanceMetric = sixel.DistanceMetric;
pub const KittyGraphics = tui.kitty.KittyGraphics;
pub const KittyImageManager = tui.kitty.KittyImageManager;
pub const ansi_art = @import("tui/ansi_art.zig");
pub const AnsiArtRenderer = ansi_art.AnsiArtRenderer;
pub const AnsiArtPlayer = ansi_art.AnsiArtPlayer;
pub const psnr = ansi_art.psnr;
pub const ssim = ansi_art.ssim;
pub const convertVideoFrame = ansi_art.convertVideoFrame;
pub const adaptive_renderer = @import("tui/adaptive_renderer.zig");
pub const AdaptiveImageRenderer = adaptive_renderer.AdaptiveImageRenderer;
pub const RenderMode = adaptive_renderer.RenderMode;
pub const particles = @import("tui/particles.zig");
pub const ParticleKind = particles.ParticleKind;
pub const ParticleConfig = particles.ParticleConfig;
pub const ParticleSystem = particles.ParticleSystem;
pub const ConicGradient = @import("tui/gradient.zig").ConicGradient;
pub const LinearGradient = @import("tui/gradient.zig").LinearGradient;
pub const RadialGradient = @import("tui/gradient.zig").RadialGradient;
pub const effects = @import("tui/effects.zig");
pub const BlurConfig = effects.BlurConfig;
pub const TransparencyConfig = effects.TransparencyConfig;
pub const applyBlur = effects.applyBlur;
pub const applyTransparency = effects.applyTransparency;
pub const ShadowStyle = effects.ShadowStyle;
pub const BorderStyle3D = effects.BorderStyle3D;
pub const image_renderer = @import("tui/image_renderer.zig");
pub const ImageRenderOptions = image_renderer.RenderOptions;
pub const ImageProtocol = image_renderer.Protocol;
pub const renderImage = image_renderer.renderImage;
pub const detectImageProtocol = image_renderer.detectProtocol;

// Convenient re-exports from tui submodules
pub const Buffer = tui.buffer.Buffer;
pub const Cell = tui.buffer.Cell;
pub const Rect = tui.layout.Rect;
pub const Style = tui.style.Style;
pub const Viewport = tui.viewport.Viewport;
pub const VirtualRenderer = tui.virtual.VirtualRenderer;
pub const IncrementalLayout = tui.incremental_layout.IncrementalLayout;
pub const LayoutCache = tui.layout_cache.LayoutCache;
pub const CompressedBuffer = tui.buffer_compression.CompressedBuffer;
pub const RichTextParser = tui.richtext_parser.RichTextParser;

// Convenient re-exports from event system
pub const EventBus = eventbus.EventBus;
pub const TaskRunner = taskrunner.TaskRunner;
pub const Priority = taskrunner.Priority;

test {
    // Pull in all module tests
    std.testing.refAllDecls(@This());
}
