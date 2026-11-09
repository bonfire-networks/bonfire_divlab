// A list's page (tasks-v2 §14). Item titles are inputs the server leaves alone once rendered; this sends
// their changes back. Enter in a line saves it and moves to the trailing line (items keep the order they
// were written, decision 13); a line is also saved when it loses focus. A line left empty is removed if
// nobody replied to it and the viewer may delete it (decision 9), otherwise it gets its text back.
// Enter in the trailing line adds an item; a pasted text with several lines adds one item per line.

const TITLE = "input[data-role=task_title_input]";
const ADD = "input[data-role=list_add]";

const ListLines = {
	mounted() {
		this.el.addEventListener("keydown", (e) => this.onKey(e));
		this.el.addEventListener("focusout", (e) => this.onBlur(e));
		this.el.addEventListener("paste", (e) => this.onPaste(e));
	},

	addLine() {
		return this.el.querySelector(ADD);
	},

	save(input) {
		const name = input.value.trim();
		const original = input.dataset.original || "";
		if (name === original) return;

		if (name === "") {
			if (input.dataset.replies === "0" && input.dataset.mayDelete === "true") {
				this.pushEventTo(this.el, "Bonfire.Divlab:delete", { task_id: input.dataset.taskId });
			} else {
				input.value = original;
			}
			return;
		}

		input.dataset.original = name;
		this.pushEventTo(this.el, "Bonfire.Divlab:rename", { task_id: input.dataset.taskId, name });
	},

	add(text) {
		if (!text.trim()) return;
		// the server adds to the page's own list, so only the text goes
		this.pushEventTo(this.el, "Bonfire.Divlab:list_add", { text });
	},

	onKey(e) {
		if (e.key !== "Enter" || e.metaKey || e.ctrlKey || e.isComposing) {
			// Backspace in the empty trailing line goes up to the last item
			if (e.key === "Backspace" && e.target.matches(ADD) && e.target.value === "") {
				const titles = this.el.querySelectorAll(TITLE);
				if (titles.length) {
					e.preventDefault();
					titles[titles.length - 1].focus();
				}
			}
			return;
		}

		if (e.target.matches(TITLE)) {
			e.preventDefault();
			this.save(e.target);
			const add = this.addLine();
			if (add) add.focus();
		} else if (e.target.matches(ADD)) {
			e.preventDefault();
			this.add(e.target.value);
			e.target.value = "";
		}
	},

	onBlur(e) {
		if (e.target.matches(TITLE)) this.save(e.target);
	},

	onPaste(e) {
		const text = e.clipboardData && e.clipboardData.getData("text");
		if (!e.target.matches(ADD) || !text || !/\r|\n/.test(text)) return;
		e.preventDefault();
		// the server reads bullets and [x] (`Bonfire.Divlab.Tasks.parse_lines/1`)
		this.add(e.target.value + text);
		e.target.value = "";
	},
};

// named exports: Surface registers each as `Bonfire.Divlab.Web.ListPageLive#<name>`
export { ListLines };
