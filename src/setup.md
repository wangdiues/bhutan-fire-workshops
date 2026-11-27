---
layout: page.njk
title: RStudio setup
permalink: setup.html
---
# Set up RStudio once

## 1. Extract and open the project

1. Install [R](https://cran.r-project.org/) and [RStudio Desktop](https://posit.co/download/rstudio-desktop/). R does the calculations. RStudio gives you an editor, a Console for messages and a Plots pane.
2. [Get the combined participant ZIP](downloads.html) and extract it to a local folder you can write to. On Windows, right-click the ZIP and choose **Extract All**.
3. Double-click **Bhutan_Forest_Fire_Workshops.Rproj** in the extracted folder. Its name appears in the upper-right corner of RStudio. Opening it sets the starting folder for all relative paths.

<pre><code>Bhutan Forest Fire Workshops/
  Bhutan_Forest_Fire_Workshops.Rproj
  01_Install_Workshop_Packages.R
  lessons/index.html
  thimphu_WUI/
    data/  outputs/  r_studio_run/
  thimphu_paro_burn_severity/
    data/  outputs/  r_studio_run/</code></pre>

Both workshops use this project. Keep the folders together so the scripts can find their files.

## 2. Install the packages

Open **01_Install_Workshop_Packages.R** in RStudio while online and click **Source** once. The script installs only missing packages. A successful run ends with **Setup complete. All workshop packages are ready.**

<div class="code-tools"><button class="button" type="button" data-copy="install-code">Copy All Code</button>
<a href="start/01_Install_Workshop_Packages.R" download>Download the installer (.R)</a><span class="copy-status" aria-live="polite"></span></div>
<pre><code id="install-code">{{ installer | escape }}</code></pre>

<details><summary>What each package does</summary>
<dl class="file-list">
{% for package in packageDescriptions %}
<dt><code>{{ package.name }}</code></dt><dd>{{ package.description }}</dd>
{% endfor %}
</dl>
</details>

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

- **R cannot find a file.** Reopen the extracted `.Rproj` and keep the folder structure together.
- **R reports a missing package.** Run the one-time installer online. If an installed package cannot load, copy the package name and error into your workshop help request.
- **Copy All Code selects the code instead.** Press Ctrl+C, or download and open the complete `.R` file.
- **The original analysis is slow.** Complete Blocks 01–09 from the reviewed results. Block 10 replays the original analysis and writes a log. Use a separate project copy for replay.

[RStudio projects](https://docs.posit.co/ide/user/ide/guide/code/projects.html) · [Run selected code](https://docs.posit.co/ide/user/ide/guide/code/execution.html)
