import QtQuick
import qs.config
import qs.modules.components

QtObject {
    id: root

    function generate(Colors) {
        if (!Colors)
            return;
        const fmt = c => c.toString();
        const rgba = (c, a) => `rgba(${Math.round(c.r * 255)}, ${Math.round(c.g * 255)}, ${Math.round(c.b * 255)}, ${a})`;

        const bg = fmt(Colors.background);
        const surface = fmt(Colors.surface);
        const surfaceLow = fmt(Colors.surfaceContainerLow);
        const surfaceMid = fmt(Colors.surfaceContainer);
        const surfaceHigh = fmt(Colors.surfaceContainerHigh);
        const fg = fmt(Colors.overBackground);
        const fgMuted = fmt(Colors.overSurfaceVariant);
        const primary = fmt(Colors.primary);
        const overPrimary = fmt(Colors.overPrimary);
        const border = rgba(Colors.outlineVariant, 0.55);
        const rim = rgba(Colors.overBackground, Config.theme.lightMode ? 0.12 : 0.08);
        const font = Config.theme.font || "sans-serif";

        const css = `:root {
  --pangu-bg: ${bg};
  --pangu-surface: ${surface};
  --pangu-surface-low: ${surfaceLow};
  --pangu-surface-mid: ${surfaceMid};
  --pangu-surface-high: ${surfaceHigh};
  --pangu-fg: ${fg};
  --pangu-fg-muted: ${fgMuted};
  --pangu-primary: ${primary};
  --pangu-over-primary: ${overPrimary};
  --pangu-border: ${border};
  --pangu-rim: ${rim};
  --toolbar-bgcolor: ${surfaceLow} !important;
  --toolbar-color: ${fg} !important;
  --toolbar-field-background-color: ${surfaceMid} !important;
  --toolbar-field-color: ${fg} !important;
  --toolbar-field-focus-background-color: ${surfaceHigh} !important;
  --toolbar-field-focus-color: ${fg} !important;
  --toolbar-field-border-color: ${border} !important;
  --toolbar-field-focus-border-color: ${primary} !important;
  --lwt-accent-color: ${bg} !important;
  --lwt-text-color: ${fg} !important;
  --tab-selected-bgcolor: ${surfaceHigh} !important;
  --tab-selected-textcolor: ${fg} !important;
  --arrowpanel-background: ${surfaceMid} !important;
  --arrowpanel-color: ${fg} !important;
  --arrowpanel-border-color: ${border} !important;
  --sidebar-background-color: ${bg} !important;
  --sidebar-text-color: ${fg} !important;
  --sidebar-border-color: ${border} !important;
  --newtab-background-color: ${bg} !important;
  --newtab-background-color-secondary: ${surfaceMid} !important;
  --newtab-text-primary-color: ${fg} !important;
  --tabpanel-background-color: ${bg} !important;
}

#navigator-toolbox {
  background-color: var(--pangu-bg) !important;
  border-bottom: 1px solid var(--pangu-border) !important;
  font-family: "${font}", sans-serif !important;
}

#TabsToolbar, #toolbar-menubar {
  background-color: var(--pangu-bg) !important;
}

.tab-background {
  border-radius: 10px !important;
  box-shadow: none !important;
}

.tabbrowser-tab[selected="true"] .tab-background {
  background-color: var(--pangu-surface-high) !important;
  border-top: 1px solid var(--pangu-rim) !important;
}

#nav-bar {
  background-color: var(--pangu-surface-low) !important;
  box-shadow: none !important;
}

#urlbar-background {
  background-color: var(--pangu-surface-mid) !important;
  border: 1px solid var(--pangu-border) !important;
  border-radius: 10px !important;
  box-shadow: none !important;
}

#urlbar[focused="true"] > #urlbar-background {
  background-color: var(--pangu-surface-high) !important;
  border-color: var(--pangu-primary) !important;
}

::selection {
  background-color: var(--pangu-primary) !important;
  color: var(--pangu-over-primary) !important;
}

@-moz-document url("about:newtab"), url("about:home"), url("about:blank") {
  body {
    background-color: var(--pangu-bg) !important;
    color: var(--pangu-fg) !important;
  }
}
`;
        firefoxFile.write(css);
    }

    property GeneratedFile firefoxFile: GeneratedFile {
        path: Paths.cachePath("firefox.css")
    }
}
