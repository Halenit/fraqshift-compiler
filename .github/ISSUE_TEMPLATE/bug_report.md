---
name: Bug Report
about: Create a report to help us improve Fraqshift OS and its compiler
title: '[BUG] '
labels: 'bug, help wanted'
assignees: ''
---

##    Bug Description
A clear and concise description of what the bug is and what went wrong during compilation or booting.

##    Steps to Reproduce
Steps to reproduce the behavior:
1. Create a source file with the code provided below.
2. Run the compiler loop using `.\build_and_run.bat`.
3. See the error in the terminal or inside the QEMU sandbox.

##    Broken Source Code (`main.fraq`)
Please paste the exact `.fraq` code that triggers the bug here:
```text
; Paste your Fraqshift code here
```

##    Expected Behavior vs. Actual Behavior
* **Expected:** What should the CPU/VGA screen display? (e.g., "It should print the integer 142")
* **Actual:** What did it actually do? (e.g., "QEMU throws an invalid kernel header or loops infinitely")

##    Screenshots / Terminal Output
If applicable, paste your VS Code terminal error message or a screenshot of the QEMU hardware sandbox freeze.

##    Environment Context
* **Host OS:** [e.g., Windows 11]
* **NASM Version:** [e.g., 2.16.03 local]
* **Python Version:** [e.g., Python 3.9]
