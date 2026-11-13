# Browser Picker

Browser Picker lets you choose which installed browser opens a web link. It is an optional feature; enable it in **Settings → Features**, then configure it under **Settings → Quick Tools → Browser Picker**.

## Set up web links

Click **Use Vorssaint for web links** and accept the macOS confirmation. This requests the default handler for both HTTP and HTTPS links. Links that another app opens directly in a particular browser bypass the system default and will not show the picker.

To stop sending links to the picker, choose another default browser in macOS System Settings. If Browser Picker is disabled while Vorssaint remains the default handler, incoming links are forwarded to the previously saved browser for their scheme, or the first installed browser if that browser is unavailable. Vorssaint's own variants are excluded from forwarding to prevent a loop.

## Appearance and browser order

- Drag browser rows to reorder them using the same live drag behavior as the Menu Bar controls.
- Use each row's switch to show or hide that browser. Hidden browsers keep their place in the saved order.
- **Show number shortcuts** controls the number badges. Hiding them does not disable number-key selection.
- **Picker position** chooses the center of the screen containing the pointer or a nearby position kept within that screen's usable area.
- The picker uses the window switcher's Small Simple List sizing. Long browser lists scroll horizontally when they exceed the available screen width.

**Scan for new browsers** discovers newly installed browsers. If all browsers are hidden, the picker shows instructions for enabling one in Settings.

## Selection

Click a browser, use the left/right arrow keys and Return or Space, or press 1–9 for one of the first nine visible browsers. Escape cancels. There is no global keyboard shortcut for Browser Picker.

**Open browser picker** in Settings opens the picker without a link; selecting a browser then launches it. Incoming web links are passed intact to the chosen browser, including their query and fragment.

## Saved settings

Browser order, visibility, number badges, and placement participate in settings backup. Previously selected system URL handlers belong to the current Mac and are excluded from backups. Pending links are kept in memory only and cleared when the picker is dismissed.
