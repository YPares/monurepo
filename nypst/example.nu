use mod.nu *

[
  {set document {
    title: [This is Nushell]  # Embed as a Typst content
    author: (st A mad one)  # Embed as a Typst string (between double quotes)
  }}

  {import "@preview/cmarker:0.1.6"}
  {import "@preview/based:0.2.0" base64}

  {set page {width: 20cm, margin: 1cm}} # Records are used to set Typst named arguments

  {set list {marker: [---]}}

  {set table {fill: (=>_ [x y] "if y == 0 { gray }")}} # Embed as a Typst anonymous function, with positional args (x, y)

  {set table.header {repeat: true}}

  {show table (set_ align center)} # set_ is like set but with only positional arguments. So it's just (set align {} center)

  {show (> table.cell.where {y: 0}) (set_ align center)}

  {> title} # Call a Typst function with no args. So that's just #title() in Typst code

  "- Whaaaaat? No, no this is Typst"

  "- Nu-huh, that's Nushell!"

  "- Wait... could it be... _*both???*_"

  _This is a line but wait what it is not quoted ah but you see it contains no punctuation that
  conflicts with Nushell syntax such as commas so "it's" mostly fine expect for that previous
  single quote which I had to quote huhu._

  "- ...but prefer not doing that, quote your lines it's better."

  "- Wait a minute. Where are the hash signs to introduce Typst code?"

  "- Oh, you can just use closures with no args instead. I.e. `{...}` or `{|| ...}` blocks.
     When using closures, `nypst` will automatically determine based on context whether
     you are in code mode or not, and introduce the hash signs when needed.
     Hashes are for comments in Nushell, so you can use them but they need to be inside
     quoted strings #emph[like this]. Watch out, here comes a right-aligned rect:"

  # >_ is like > but with only positional arguments:
  {>_ align right (> rect {inset: 3pt, stroke: red} [
    I am a rect.
    {> linebreak}
    Get [{show text smallcaps} rekt.]
    # Brackets (I mean, lists) can be used to delimit the scope in which
    # show & set rules do apply, like in regular Typst
  ])}

  "Wow, it looked angry, you saw how red it was? Oh and here comes a quite dashing grid:"

  {>_ align center (
    > grid
      { columns: 2
        inset: .5em
        fill: (=>_ [x y] "if calc.odd(x + y) {green} else {aqua}")
        stroke: (=>_ [x y] {
          # We can use closures basically anywhere, that's convenient
          # if we want to declare local Nu variables:
          let borders = [top bottom left right] | shuffle | take 2 
          { ($borders.0): (> stroke {dash: (st dashed)}) 
            ($borders.1): (> stroke {dash: (st dotted)})
          }
        })
      }
      [Hey that is a first cell]      [Hey a second one]
      ["Oh, here comes another"]      [...]
      [...My god this will never end] [Oh wait nope it does]
  )}

  "- Ok, ok, stop with the puns. And what is all that fuss about anyway?"

  "- First, to avoid string-escaping hell when using Nushell to generate Typst code.
     And also, let's say I want to generate content programmatically. `nypst` can translate
     most Nushell types into their Typst equivalents:"

  {(> table {columns: (array 1fr 3fr)}
    (>_ table.header [Nu type] [Typst translation])
    [record]   [{a: 34, b: red}]
    [datetime] [(date now)]
    [duration] [(12sec + 7min - 40hr)]
    ["null"]   [null "(Typst 'none' is invisible)"]
    ["list (need to call `array`)"] [{array ...(seq 1 15)}]
  )}

  "- But what about tables? Say I want to include in this doc the output of `ls`.
     Well, Nushell as built-in support for Markdown generation from its regular datastructures.
     And Typst has the `cmarker` library to render inlined Markdown:"

  {>_ cmarker.render (ls | to md | raw)}
  # raw puts its input text between backticks so it becomes a Typst `raw` content 

  "- Huh. But Nushell can just output CSV, and Typst can read CSV out of the box"

  "- True, you can do that, but that requires to handle the headers specifically,
     which can be cumbersome unless you know the headers and the amount of columns
     ahead of time, and also properly escape the CSV before wrapping it as `bytes`.
     A technique is to use a Typst `raw` text block for that:"

  {
    let files = ls
    let cols = $files | columns
    (> table {columns: ($cols | length)}
      ...($cols | each {[$in]})
      (
        (>_ csv
          (>_ bytes (
            $files | to csv --noheaders | raw | dot text
          ))
        ) |
          dot (>_ flatten) |
          spliced
      )
    )
  }
  # The `dot` command is used to access fields or call methods on the Typst expression fed in input.
  # The `spliced` command prints its input expression with ".." in front of it so its output value is
  # spliced by Typst as positional args of the `table` call.

  "- Indeed. That's... cumbersom... er."

  "- ...AND I CAN DO THE SAME WITH `ps`!! See:"

  {>_ cmarker.render (ps | where name =~ nu | to md | raw)}

  "- Ok yeah that's pretty c..."

  "- WANT MORE??? IN @nu-logo IS THE NUSHELL LOGO WHICH I'M DOWNLOADING ON THE FLY!!!!"

  {(> figure
    {caption: [The nushell logo downloaded on the fly]}
    (> image {width: 17em} (>_ base64.decode (
      http get https://avatars.githubusercontent.com/u/50749515 | encode base64 | st
    ))))} (lbl nu-logo)

  "- Doctor, I think we lost him..."
] | compile example.pdf
