# Main HTML templating function
#
# Creates a HTML node with its attributes and children
export def t [
  tag: string
  --attrs (-a): record = {}
  ...contents: string
] {
  let rendered_attrs = $attrs | transpose key val |
    each {|a| $"($a.key)='($a.val)'"} |
    str join " "
  $"<($tag) ($rendered_attrs)>($contents | where {$in != null} | str join ' ')</($tag)>"
}

export def flat-group-by [
  ...groups: cell-path
] {
  group-by ...$groups --to-table | each {|g|
    let items = $g.items | reject ...$groups
    [($g | reject items | merge $items.0)] ++ ($items | slice 1..)
  } |
    flatten
}

export def to-html [
  --query: string
  --header: string = "Results"
  --out: path = "results.html"
] {
  (t html
    (t head
      (t title $header)
      (t link -a {
          href: "https://cdn.jsdelivr.net/npm/bootstrap@5.3.6/dist/css/bootstrap.min.css"
          rel: "stylesheet"
          integrity: "sha384-4Q6Gf2aSP4eDXB8Miphtr37CMZZQ5oXLH2yaXMJ2w8e2ZtHTl7GptT4jmndRuHDT"
          crossorigin: "anonymous"
      })
    )
    (t body
      (t script -a {
        src: "https://cdn.jsdelivr.net/npm/bootstrap@5.3.6/dist/js/bootstrap.bundle.min.js"
        integrity: "sha384-j1CDi7MgGQ12Z7Qab0qlWQ/Qqz24Gc6BM0thvEMVjHnfYGF0rmFCozFSxQBxwHKO"
        crossorigin: "anonymous"
      })
      (t div
        (t h1 $header)
        ($in | to html --partial | str replace "<table>" "<table class='table table-striped table-hover table-bordered'>")
      )
      (if ($query != null) {
        (t div
          (t h2 "Query (for reference)")
          (t pre
            ($query | sql-formatter -l postgresql)
          )
        )
      })
    )
  ) |
  save -f $out
}
