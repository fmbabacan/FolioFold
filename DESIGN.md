# FolioFold Design System

## Direction

FolioFold is a native macOS productivity tool with a restrained, document-first interface. A narrow collapsible sidebar and compact tab strip frame a quiet workspace. Controls use standard macOS affordances and appear contextually instead of forming permanent tool palettes.

## Physical Context

An independent professional uses FolioFold for extended document work in changing office light, so the interface follows the system appearance and keeps contrast stable in both light and dark environments.

## Color

- Strategy: restrained neutral surfaces with one low-saturation ink-blue accent occupying less than ten percent of the interface.
- Accent: selection, keyboard focus, links, active tools, and primary actions only.
- Surfaces: system window background, a subtly differentiated sidebar, document canvas, and white PDF pages.
- Semantics: success, warning, and error use system semantic colors plus icons and text labels.
- Color never carries meaning alone.

## Typography

- SF Pro through native system text styles. No bundled fonts.
- Compact hierarchy with standard macOS label, body, title, and toolbar sizing.
- Prose is limited to comfortable reading widths; tool UI remains dense and consistent.

## Layout

- Sidebar: open by default, narrow, resizable, and fully collapsible.
- Sidebar order: Create, Open, Merge, Split, Convert, then Recents.
- Workspace: document and tool sessions share a reorderable tab strip.
- Document tools: contextual toolbar and inspector based on selection.
- Create documents: flowing blocks with optional page-pinned overlays.
- Existing PDFs: source-preserving page view with editable overlay layers.

## Components

- Native buttons, menus, split views, tab interactions, sheets, file panels, and SF Symbols.
- Interactive states include default, hover, focus, active, disabled, loading, and error where applicable.
- Empty states teach the next available action in one concise sentence.
- Corner radii remain modest. Borders and shadows are used only when required to clarify hierarchy.

## Motion

- State transitions use native motion in the 150 to 250 millisecond range.
- Sidebar and inspector transitions respect Reduce Motion.
- No decorative entrance sequences or continuously animated elements.

## Accessibility

- Full keyboard operation and visible focus.
- VoiceOver names, values, actions, and ordering for every custom interaction.
- Text and controls meet WCAG AA contrast targets.
- High-contrast and reduced-motion system settings are honored.

## Localization

All user-visible strings live in String Catalogs. Layouts permit text expansion; dates, numbers, currencies, plurals, and writing direction come from locale-aware system APIs.
