def process-elem [--in-code elem] {
  let hash = if (not $in_code) {"#"}
  match ($elem | describe -d | get type) {
    "closure" => {
      $"($hash)(process-elem --in-code (do $elem))"
    }
    "list" => {
      $"($hash)[($elem | process-positional)]"
    }
    "record" => {
      $"($hash)\((process-named $elem))"
    }
    "datetime" => {
      let rec = $elem | into record
      $"($hash)datetime\((process-named
        ($rec | select year month day hour minute second)
      ))"
    }
    "duration" => {
      let rec = $elem | into record
      let new_rec = {
        seconds: $rec.second?
        minutes: $rec.minute?
        hours: $rec.hour?
        days: $rec.day?
        weeks: $rec.week?
      } | transpose key val | where val != null | transpose -rd
      $"($hash)\((if $rec.sign == "-" {"-"})duration\((process-named $new_rec)))"
    }
    "null" => $"($hash)none"
    _ => $elem
  }
}

def process-positional [--sep = "\n", --in-code] {
  each {process-elem --in-code=($in_code) $in} | str join $sep
}

def process-named [record: record] {
  if ($record | is-not-empty) {
    $record |
      transpose key val |
      each {|pair|
        let k = $pair.key
        let v = process-elem --in-code $pair.val # | process-elem --in-code
        $"($k): ($v)"
      } |
      str join ", " |
      $"($in), "
  } else {""}
}

# Print a call to a Typst function
export def ">" [
  fn_name: string
  named_args = {}: record
  ...positional_args: any
] {
  $"($fn_name)\((
    process-named $named_args
  )(
    $positional_args | process-positional --sep ', ' --in-code
  ))"
}

# Print a call to a Typst function with only positional args
export def ">_" [
  fn_name: string
  ...positional_args: any
] {
  > $fn_name {} ...$positional_args
}

# Print a Typst import statement
export def import [
  module: string
  --as: string
  ...imports: string
] {
  let imports = if ($imports | is-not-empty) {
    $": ($imports | str join ', ')"
  }
  $"import \"($module)\" (
    if $as != null {$'as ($as)'}
  ) ($imports)"
}

# Print a Typst set rule with only positional args
export def set [
  fn_name: string
  named_args = {}: record
  ...positional_args
] {
  $"set (> $fn_name $named_args ...$positional_args)"
}

# Print a Typst set rule with only positional args
export def set_ [
  fn_name: string
  ...positional_args
] {
  set $fn_name {} ...$positional_args
}

# Print a Typst show rule
export def show [
  pattern: string
  ...args 
] {
  $"show ($pattern): ($args | process-positional --in-code)"
}

# Print a Typst label
export def lbl [name] {
  $"<($name)>"
}

# Print a Typst anonymous function
export def "=>" [
  named_args = {}
  positional_args = []
  ...body
] {
  $"\((
    process-named $named_args 
  )(
    $positional_args | str join ', '
  )) => ($body | process-positional --in-code)"
}

# Print a Typst anonymous function that only takes positional args
export def "=>_" [positional_args = [] ...body] {
  => {} $positional_args ...$body
} 

# Concatenate $in and args and quote the result so it can be embedded as a Typst string
#
# The input strings must not contain double quotes
export def st [--sep = " " ...args] {
  '"' + ($in | append $args | str join $sep) + '"'
}

# Raw concatenation of $in and args, to make arbitrary expressions
#
# The input strings must not contain double quotes
export def ct [--sep = " " ...args] {
  append $args | str join $sep
}

# Render a value with `to md` and quote it so it's a `raw(...)` Typst string
export def "to quoted-md" [] {
  '````' + ($in | to md) + '````'
}

# Print a Typst array
export def array [...elems] {
  $elems | process-positional --sep ', ' | $"\(($in))"
}

# Convert a list to Typst code
export def "to typst" []: list<any> -> string {
  process-positional
}

# Compile a list of Typst lines to a file
export def compile [out: path]: list -> nothing {
  to typst | typst compile "-" $out
}
