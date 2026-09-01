# FolioFold UI Experience Report

Date: 2026-08-31
Scope: Installed FolioFold macOS application, observed through live Computer Use testing and cross-checked against the SwiftUI implementation.

## Executive assessment

FolioFold has the right foundation for a trustworthy native Mac utility. It is restrained, familiar, and avoids decorative clutter. The interface communicates privacy and local processing well. However, the current experience feels closer to a capable engineering tool than a polished document product.

The main visual challenge is not ugliness in the conventional sense. It is insufficient hierarchy. Too many controls carry similar visual weight, selected states are understated, complex tools are presented as long forms, and several screens rely on system defaults without enough product-level composition.

Overall assessment: 6.5/10

- Native macOS fit: 8/10
- Visual consistency: 6/10
- Information hierarchy: 5/10
- Learnability: 6/10
- Accessibility readiness: 5/10
- Perceived trust and safety: 8/10
- Professional polish: 6/10

## Desired product character

FolioFold should feel like a calm, precise, private document workbench.

The intended character should be:

- Native rather than custom for its own sake
- Dense when useful, but never crowded
- Safe around destructive document operations
- Quiet, with strong hierarchy instead of decoration
- Understandable to ordinary Mac users, not only PDF experts
- Consistent across Create, PDF editing, Merge, Split, and Convert

A useful reference point is the clarity of Preview, the sidebar discipline of Finder, and the focused inspector behavior of Pages or Keynote. The product does not need to imitate these apps, but it should reach the same level of immediate legibility.

## Global layout experience

### What works

- The navigation-sidebar plus workspace model is familiar on macOS.
- Major activities are easy to discover: Create, Open, Merge, Split, and Convert.
- The restrained blue accent supports the privacy-oriented positioning.
- Native controls reduce the learning burden.
- The interface avoids excessive cards, gradients, animation, and decorative imagery.

### What weakens the experience

- The sidebar, horizontal tab strip, workspace toolbar, main content, and inspector all compete for attention.
- The interface has several simultaneous navigation concepts: sidebar destinations, document sessions, tabs, PDF thumbnails, and inspector sections.
- The active context is not always obvious enough. Users must infer whether they are in a tool, document, page, or tab state.
- Divider lines and grouped forms establish structure mechanically, but not always meaningfully.
- Narrow windows are likely to compress toolbars and long labels instead of adapting the layout.

### Recommended direction

Use three stable layers:

1. Sidebar for global activities and recent documents
2. Tab strip for open sessions
3. Contextual workspace with one primary action and one contextual inspector

The visual hierarchy should make the current session unmistakable. Secondary controls should recede until relevant.

## Sidebar

### Current experience

The sidebar is understandable and appropriately compact. Create, Open, Merge, Split, and Convert are sensible top-level entries. Recents appearing below them follows a familiar Mac pattern.

The weakness is that action buttons and persistent navigation destinations look conceptually similar. Create and Open perform immediate actions, while Merge, Split, and Convert open reusable sessions. Users are not told about this distinction.

“No recent documents” appears as a selectable row in the accessibility tree, which makes an informational empty state feel interactive.

### Improvements

- Separate document actions from tools with clear sections such as Documents and PDF Tools.
- Treat “No recent documents” as non-interactive supporting text.
- Show the active tool or document consistently in the sidebar where appropriate.
- Add contextual drag-and-drop states for compatible files.
- Keep the sidebar visually quiet and avoid adding decorative badges unless they communicate state.

## Workspace tabs

### Current experience

The custom tab chips are one of the weakest visual areas. The selected tab uses a very subtle background, making it difficult to locate when several sessions are open. Close controls add repeated visual noise. Unsaved state is represented by a tiny dot that can be overlooked.

The tab strip also creates accessibility ambiguity because its children can inherit the container’s generic “Workspace tabs” identity.

### Improvements

- Give the active tab stronger contrast and a clear selected shape or underline.
- Reveal close buttons on hover for inactive tabs while keeping the current tab’s close action available.
- Use an accessible unsaved indicator with a tooltip and spoken state.
- Truncate long titles predictably and expose the full name on hover.
- Add an overflow menu when tabs no longer fit.
- Support standard tab-switching shortcuts.
- Preserve the restrained visual language rather than making tabs bright or oversized.

## Create workspace

### Current experience

The Create screen is functional and reasonably approachable. Users can choose a block type, add a block, open templates, undo, redo, save, and export. The block cards separate editable content clearly.

The header is crowded. Document title, block type, Add, Templates, Undo, Redo, Save, and Export all occupy one row and have similar prominence. The user’s main task, writing, loses visual priority to controls.

Inside each block, Pin to Page and Delete Block are persistently visible. Repetition across many blocks will create noise. The distinction between document flow and pinned page content is not explained until the user encounters disabled controls or template concepts.

### Recommended composition

- Put document-level actions in the native window toolbar: Save, Export, and document status.
- Put block insertion near the content area as one clear Add Block control.
- Keep Undo and Redo in familiar toolbar positions or rely on standard menu commands and shortcuts.
- Move block-specific actions into a contextual menu or reveal them on hover and focus.
- Add a subtle insertion affordance between blocks.
- Provide a visible drag handle and keyboard reordering.
- Show block type as a compact label rather than a competing control when the block is not selected.

### First-use experience

The empty document should teach three concepts in one concise message:

- Content is built from blocks.
- Blocks flow into pages automatically.
- Blocks can optionally be pinned to a page.

This explanation should disappear naturally once the user starts working.

## PDF workspace

### Current experience

The PDF workspace is powerful but visually dense. It combines page thumbnails, a central PDF viewer, document actions, and a permanent inspector containing Pages, Annotation, Form Field, Redaction, and operation status.

This exposes a large feature set, but it asks the user to process too much at once. The right inspector resembles a settings form more than a contextual editing tool. The central document can feel squeezed between thumbnails and a 290–400 point inspector.

### Improvements

- Split the inspector into contextual modes: Pages, Annotate, Forms, Redact.
- Show only controls relevant to the selected mode.
- Add a clear toolbar mode selector with familiar icons and labels.
- Allow the inspector to collapse and remember its width.
- Add visible zoom, fit-width, fit-page, search, and page navigation controls.
- Keep the document visually dominant.
- Show temporary previews directly on the page before exporting modifications.

## Page thumbnails and page actions

### Current experience

Page thumbnails are understandable, and the selected page border is useful. Move, rotate, duplicate, and delete operations are discoverable in the toolbar and menu.

The selected-page treatment relies heavily on a thin blue border. Page operations change the working document immediately, but there is no prominent editing history or safety signal.

### Improvements

- Strengthen the selected thumbnail state with border plus subtle background.
- Show page numbers with consistent alignment.
- Add drag insertion markers while reordering.
- Support multi-selection for batch operations where feasible.
- Add Undo for page transformations and confirmation for irreversible deletion.
- Announce page movement and deletion to assistive technologies.

## Annotation experience

### Current experience

Annotation types are placed in a pop-up selector. Depending on the selected type, additional fields appear beneath it. This is compact but hides the breadth of available tools and makes annotation feel like form submission.

“Add Annotation and Export…” combines editing and exporting into one action. This prevents an iterative workflow in which users add several annotations, review them, reposition them, and export only when ready.

### Recommended model

- Select an annotation tool.
- Place or draw it directly on the page.
- Edit its properties in the inspector.
- Keep it in a visible working state.
- Export the edited PDF when the user is finished.

This would make text notes, highlights, links, shapes, drawings, images, and visual signatures feel like one coherent system.

## Redaction experience

### Current experience

Redaction is technically careful and clearly states that a new rasterized PDF will be created. This is a strong trust signal.

The interaction itself is too technical. X, Y, Width, and Height in PDF points require domain knowledge and make it difficult to predict the result. Users cannot confidently verify that sensitive content is covered before export.

### Improvements

- Let users draw redaction rectangles directly over the page.
- Use resize handles and a visible redaction preview.
- Keep coordinates in an Advanced disclosure group.
- Warn when a rectangle extends outside the page.
- Allow multiple redaction areas before applying.
- Add a final review step explaining that text and metadata will be removed.

## Form fields

### Current experience

The form-field section supports several field types but exposes only a small collection of textual properties. Placement behavior is not visually communicated, and the generic default field name “field” risks producing confusing PDFs.

### Improvements

- Place fields directly on the page.
- Show resize handles and alignment guides.
- Generate meaningful unique names or require explicit names.
- Validate duplicate names inline.
- Display field type, required state, default value, tooltip, and options contextually.
- Provide a preview mode for testing the completed form.

## Visual signatures

### Current experience

FolioFold responsibly explains that a visual signature is an image annotation, not a certified digital signature. This distinction should be preserved.

The explanation appears late in the flow and the capture/import controls are nested under annotation choices, which may make the feature harder to discover.

### Improvements

- Name the feature Visual Signature everywhere.
- Show the legal/technical distinction before capture.
- Present saved visual signatures as reusable private local assets.
- Let users preview scale, crop, and background transparency.
- Place and resize signatures directly on the page.

## Merge workspace

### Current experience

The empty state explains the task well and the primary action is easy to find. The form layout is calm but visually sparse before files are selected.

Once populated, filenames with small up, down, and delete controls are likely to feel utilitarian. There are no thumbnails, page counts, file sizes, or strong reorder affordances.

### Improvements

- Use a compact source list with thumbnail, filename, page count, and size.
- Add drag handles and clear drop indicators.
- Let users add more files through the empty area and toolbar.
- Preview the total page count.
- Keep Export Merged PDF as the single prominent action.

## Split workspace

### Current experience

The screen is simple, but it undersells the operation. A pages-per-output stepper is the only splitting method. Users cannot visualize resulting groups or filenames.

### Improvements

- Offer clear modes: every page, every N pages, ranges, and selected pages.
- Show a live output preview.
- Display total pages and estimated output count.
- Provide editable output naming.
- Keep advanced range syntax optional.

## Convert workspace

### Current experience

The privacy message is strong: supported files are converted locally without uploading. The screen clearly identifies source files and export.

The result of selecting multiple files is ambiguous. Users may not know whether they receive one combined PDF or several PDFs, or what order will be used.

### Improvements

- State the output model before file selection.
- Show source order and allow reordering.
- Show thumbnails or type icons and estimated pages.
- Offer Combine into one PDF and One PDF per source when supported.
- Preserve the privacy explanation, but make it secondary to the task.

## Templates experience

### Current experience

Templates are powerful but conceptually demanding. Fields, kinds, formats, default values, generated values, block bindings, and sequence numbers appear in one sheet. This works as an implementation surface but does not yet teach the mental model.

### Improvements

- Organize the flow into Fields, Bindings, and Preview.
- Explain each field type with an example.
- Show block bindings directly in the document.
- Offer starter templates demonstrating common use cases.
- Preview generated content before applying it.
- Use inline validation for duplicate names and invalid formats.

## Empty, loading, success, and error states

### Current experience

Empty states generally use clear text and disabled actions. This prevents invalid operations. However, most status feedback appears as subdued secondary text, so success, warning, and failure can look too similar.

### Improvements

- Give each state a semantic icon and concise title.
- Keep error details expandable.
- Announce status changes through accessibility notifications.
- Include a corrective action where one exists.
- Use determinate progress when measurable and offer Cancel.
- Avoid layout jumps when status messages appear.

## Visual system

### Color

The muted ink blue is appropriate and should remain the primary accent. It communicates calmness and trust. It should be reserved for current selection, primary actions, focus, and meaningful status.

Avoid introducing several decorative accent colors. Semantic colors should appear only for success, warning, error, and destructive actions.

### Typography

The system font is the correct choice. The issue is hierarchy rather than font selection.

Recommended hierarchy:

- Workspace title: strong but compact
- Section title: consistent semibold label
- Body and instructions: regular system body
- Metadata: secondary caption
- Buttons and controls: standard system sizing

Large title styles should be limited to welcome/about surfaces, not routine tool screens.

### Spacing

Adopt a small, explicit spacing system rather than relying on unrelated default paddings:

- 4 points: icon-label and dense control spacing
- 8 points: related controls
- 12 points: compact groups
- 16 points: standard section spacing
- 24 points: major workspace separation
- 32 points: onboarding and empty-state breathing room

### Corners and surfaces

The current restrained corner radius is appropriate. Avoid turning every section into a rounded card. Use grouped surfaces only when they clarify ownership or selection.

### Icons

SF Symbols fit the application. Icon-only controls need consistent tooltips, accessible labels, predictable sizing, and adequate click targets. Destructive icons should not rely on red alone.

## Responsive behavior

The interface should be explicitly tested at narrow, regular, and wide window sizes.

At narrow widths:

- Collapse or hide the inspector.
- Move secondary toolbar actions into menus.
- Preserve the document canvas.
- Keep the primary action visible.
- Allow tab overflow rather than shrinking tabs beyond recognition.

At wide widths:

- Avoid stretching forms across the full workspace.
- Keep readable text widths.
- Let the document canvas consume additional space.

## Accessibility experience

The current implementation includes many accessibility labels, which is a strong base. The live accessibility tree nevertheless revealed naming collisions and generic tab identities.

Required improvements:

- Unique names and identifiers for every tab and close action
- Selected-state announcements
- Context-aware labels for repeated icon actions
- Full keyboard access
- Visible focus rings
- Status announcements
- Non-color state indicators
- Increased Contrast and larger-text validation
- Logical reading order across sidebar, tabs, content, and inspector

## Recommended redesign sequence

### Phase 1: Establish trust and orientation

- Fix stale workspace navigation.
- Strengthen active tab and selected-page states.
- Correct tab accessibility structure.
- Add safe Undo or confirmation for destructive page actions.
- Clarify unsaved and operation status.

### Phase 2: Simplify the workspaces

- Move document actions into a consistent toolbar.
- Introduce contextual PDF inspector modes.
- Reduce repeated block controls.
- Standardize primary-action language.
- Add responsive narrow-window behavior.

### Phase 3: Improve direct manipulation

- Draw redactions on the page.
- Place annotations, form fields, and signatures visually.
- Add drag-and-drop and reorder previews.
- Add PDF zoom, search, and navigation controls.

### Phase 4: Polish and scale

- Add semantic feedback components.
- Move strings into localization catalogs.
- Test dark mode, increased contrast, reduced motion, long translations, and keyboard-only use.
- Add visual regression snapshots.

## Final design verdict

FolioFold already feels safer and calmer than many utility applications. Its privacy positioning, native controls, and restrained styling are assets worth protecting. The next design step should not be decorative modernization. It should be stronger hierarchy, clearer state, progressive disclosure, safer editing, and direct interaction with the document.

If those changes are made, the product can move from “capable Mac utility” to “professional document workspace” without losing its native identity.

