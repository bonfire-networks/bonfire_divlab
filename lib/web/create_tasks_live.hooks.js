// The composer's item lines (tasks-v2 §13). The server never re-renders them, so this keeps them in step:
// Enter splits the line at the caret into a new one below (never leaving a blank line), Backspace at the start merges a line into the
// one above, the arrows move between lines, and a pasted text with several lines becomes several, blank ones dropped.
// Inputs are renumbered `choices[i][name]` after every change, the shape the composer's validate counts.

const LINE = "input[data-role=task_line]";
const ROW = "[data-role=task_line_row]";

// tell the composer's form a value changed, so its validate runs (the submit button enables on content)
function changed(input) {
	input.dispatchEvent(new Event("input", { bubbles: true }));
}

const Lines = {
	mounted() {
		this.el.addEventListener("keydown", (e) => this.onKey(e));
		this.el.addEventListener("paste", (e) => this.onPaste(e));
	},

	inputs() {
		return [...this.el.querySelectorAll(LINE)];
	},

	renumber() {
		this.inputs().forEach((input, i) => {
			input.name = `choices[${i}][name]`;
			input.id = `task_line_${i}`;
			const label = input.closest(ROW).querySelector("label");
			if (label) label.htmlFor = input.id;
			// only the first line explains itself
			if (i > 0) input.placeholder = "";
		});
	},

	addAfter(input, value) {
		const row = input.closest(ROW);
		const copy = row.cloneNode(true);
		const next = copy.querySelector(LINE);
		next.value = value;
		row.after(copy);
		this.renumber();
		return next;
	},

	onKey(e) {
		const input = e.target.closest(LINE);
		if (!input) return;
		const lines = this.inputs();
		const i = lines.indexOf(input);
		const atStart = input.selectionStart === 0 && input.selectionEnd === 0;

		// ⌘/Ctrl+Enter is the composer's own submit
		if (e.key === "Enter" && !e.metaKey && !e.ctrlKey && !e.isComposing) {
			e.preventDefault();
			const caret = input.selectionStart;
			// no blank lines: Enter on an empty line, or at the start of one, adds nothing (the server skips blank lines anyway)
			if (input.value.slice(0, caret).trim() === "") return;
			// an empty line already waits below: go there rather than add another
			const below = lines[i + 1];
			if (below && below.value.trim() === "" && input.value.slice(caret).trim() === "") {
				below.focus();
				return;
			}
			const after = input.value.slice(caret);
			input.value = input.value.slice(0, caret);
			const next = this.addAfter(input, after);
			next.focus();
			next.setSelectionRange(0, 0);
			changed(input);
		} else if (e.key === "Backspace" && atStart && i > 0) {
			e.preventDefault();
			const prev = lines[i - 1];
			const at = prev.value.length;
			prev.value += input.value;
			input.closest(ROW).remove();
			this.renumber();
			prev.focus();
			prev.setSelectionRange(at, at);
			changed(prev);
		} else if (e.key === "ArrowUp" && i > 0 && atStart) {
			e.preventDefault();
			lines[i - 1].focus();
		} else if (e.key === "ArrowDown" && i < lines.length - 1 && input.selectionEnd === input.value.length) {
			e.preventDefault();
			lines[i + 1].focus();
		}
	},

	onPaste(e) {
		const input = e.target.closest(LINE);
		const text = e.clipboardData && e.clipboardData.getData("text");
		if (!input || !text || !/\r|\n/.test(text)) return;
		e.preventDefault();
		// the first pasted line joins what's before the caret, the last one what's after it; the server parses bullets and [x]
		const [first, ...rest] = text.split(/\r\n|\r|\n/).filter((line) => line.trim() !== "");
		if (first === undefined) return;
		const caret = input.selectionStart;
		const after = input.value.slice(input.selectionEnd);
		input.value = input.value.slice(0, caret) + first;
		let last = input;
		rest.forEach((line, n) => {
			last = this.addAfter(last, n === rest.length - 1 ? line + after : line);
		});
		last.focus();
		changed(input);
	},
};

// a new list's name: Enter goes to the first item instead of submitting the composer
const Title = {
	mounted() {
		this.el.addEventListener("keydown", (e) => {
			if (e.key !== "Enter" || e.metaKey || e.ctrlKey || e.isComposing) return;
			e.preventDefault();
			const first = document.querySelector(`#task_lines ${LINE}`);
			if (first) first.focus();
		});
	},
};

// named exports: Surface registers each as `Bonfire.Divlab.Web.CreateTasksLive#<name>`
export { Lines, Title };
