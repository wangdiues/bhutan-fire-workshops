---
layout: page.njk
title: RStudio setup
permalink: setup.html
---
# Set up RStudio once

## 1. Install R and get the workshop folder

1. Install [R](https://cran.r-project.org/) and [RStudio Desktop](https://posit.co/download/rstudio-desktop/). R does the calculations. RStudio gives you an editor, a Console for messages and a Plots pane.
2. [Get the workshop ZIP](downloads.html) and extract it to a local folder you can write to. On Windows, right-click the ZIP and choose **Extract All**.

<pre><code>Thimphu_WUI_Workshop/
  data/       the workshop data files
  scripts/    00_setup.R and the practical scripts</code></pre>

Keep `data` and `scripts` side by side in the same folder. The scripts find the data from there.

## 2. Install the packages

While online, run this once in the RStudio Console. It installs only the packages that are missing.

<div class="code-tools"><button class="button" type="button" data-copy="install-code">Copy All Code</button><span class="copy-status" aria-live="polite"></span></div>
<pre><code id="install-code">packages &lt;- c("jsonlite", "openxlsx", "terra")
missing &lt;- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) install.packages(missing, repos = "https://cloud.r-project.org")
message("All workshop packages are ready.")</code></pre>

<dl class="file-list">
<dt><code>jsonlite</code></dt><dd>Reads the reviewed result summaries (.json).</dd>
<dt><code>openxlsx</code></dt><dd>Reads the reviewed result tables (.xlsx).</dd>
<dt><code>terra</code></dt><dd>Reads and plots the maps (.tif).</dd>
</dl>

## 3. Run your first practical

<ol class="teaching-steps">
<li><b>Read</b> Open a practical in your browser. Put the lesson beside RStudio.</li>
<li><b>Copy once</b> Click <b>Copy All Code</b>. In RStudio, choose <b>File → New File → R Script</b>, then paste.</li>
<li><b>Run one block</b> Highlight Block 01 and press <kbd>Ctrl</kbd> + <kbd>Enter</kbd>. Read the Console. Continue in order.</li>
<li><b>Read the result</b> The Console shows numbers and messages. The Plots pane shows the map or chart. The lesson tells you what to expect.</li>
</ol>

<figure class="example">
<div class="screen-plan">
<div><strong>Left · Browser</strong><p>Read the method and the expected output. Copy the complete script once.</p></div>
<div><strong>Right · RStudio</strong><p>Paste into the editor. Select a numbered block. Read the Console or Plots pane.</p></div>
</div>
<figcaption>Keep the guide beside the editor, so you can follow the notes while you run each block.</figcaption>
</figure>

A line beginning with `#` is a note. In `year <- 2025`, the arrow stores 2025 under the name `year`. In `terra::rast()`, the double colon tells R to use the `rast()` tool from the terra package.

<p class="links"><a class="button" href="wui.html#practicals">Start Thimphu WUI</a> <a class="button" href="burn.html#practicals">Start Burn Severity</a></p>

## If you get stuck

- **R cannot find a file.** In RStudio choose **Session → Set Working Directory → To Source File Location** with a script from `scripts` open, and keep `data` beside `scripts`.
- **R reports a missing package.** Run the install code in step 2 while online. If an installed package cannot load, copy the package name and error into your workshop help request.
- **Copy All Code selects the code instead.** Press Ctrl+C, or download and open the complete `.R` file.

[Run selected code](https://docs.posit.co/ide/user/ide/guide/code/execution.html)
