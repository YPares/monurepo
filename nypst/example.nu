use mod.nu *

[
  {set document {
    title: [This is Nushell]  # Embed as a Typst content
    author: (s A mad one)  # Embed as a Typst string (between double quotes)
  }}

  {import "@preview/cmarker:0.1.6"}

  {set page {width: 20cm, margin: 1cm}} # Records are used to set Typst named arguments

  {set list {marker: [---]}}

  {set table {fill: (fn {} [x y] "if y == 0 { gray }")}} # Embed as a Typst anonymous function, with positional args (x, y)

  {set table.header {repeat: true}}

  {show table (pset align center)} # pset is like set but with only positional arguments. So it's just `(set align {} center)`

  {show (call table.cell.where {y: 0}) (pset align center)}

  {call title} # Call a Typst function with no args. So that's just `#title()`

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

  # pcall is like call but with only positional arguments:
  {pcall align right (call rect {inset: 3pt, stroke: red} [
    I am a rect.
    {call linebreak}
    Get [{show text smallcaps} rekt.]
  ])}

  "Wow, it looked angry, you saw how red it was? Oh and here comes a quite dashing grid:"

  {pcall align center (
    call grid
      { columns: 2
        inset: .5em
        stroke: (call stroke {dash: (s dashed), thickness: .1pt}) }
      [Hey that is a first cell]      [Hey a second one]
      ["Oh, here comes another"]      [...]
      [...My god this will never end] [Oh wait nope it does]
  )}

  "- Ok, ok, stop with the puns. And what is all that fuss about anyway?"

  "- First, to avoid string-escaping hell when using Nushell to generate Typst code.
     And also, let's say I want to generate content programmatically. `nypst` can translate
     most Nushell types into their Typst equivalents:"

  {(call table {columns: (array 1fr 3fr)}
    (pcall table.header [Nu type] [Typst translation])
    [record]   [{a: 34, b: red}]
    [datetime] [(date now)]
    [duration] [(12sec + 7min - 40hr)]
    ["null"]   [null "(Typst 'none' is invisible)"]
    ["list (need to call `array`)"] [{array ...(seq 1 15)}]
  )}

  "- But what about tables? Say I want to include in this doc the output of `ls`.
     Well, Nushell as built-in support for Markdown generation from its regular datastructures.
     And Typst has the cmarker library:"

  {pcall cmarker.render (ls | quoted-md)}

  "- Huh."

  "- That's cool, right?"

  "- But what would have happened if the some Markdown cell had contained double quo..."

  "- ...AND I CAN DO THE SAME WITH `ps`!! See:"

  {pcall cmarker.render (ps | where name =~ nu | quoted-md)}
] | compile example.pdf
