export def process-elem [--in-code elem] {
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

export def process-positional [--sep = "\n", --in-code] {
  each {process-elem --in-code=($in_code) $in} | str join $sep
}

export def process-named [record: record] {
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
export def call [
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
export def pcall [
  fn_name: string
  ...positional_args: any
] {
  call $fn_name {} ...$positional_args
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
  $"set (call $fn_name $named_args ...$positional_args)"
}

# Print a Typst set rule with only positional args
export def pset [
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

# Print a Typst anonymous function
export def fn [
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

# Properly quote a string so it can be embedded as a Typst string
export def s [--sep = " " ...args] {
  $'"($args | str join $sep)"'
}

# Raw concatenation, to make arbitrary expressions
export def c [--sep = " " ...args] {
  $"($args | str join $sep)"
}

# Render a value with `to md` and safely quote it
export def quoted-md [] {
  $"````($in | to md)````"
}

# Embed a Typst array
export def array [...elems] {
  $elems | process-positional --sep ', ' | $"\(($in))"
}

# Compile a list of Typst lines to a file
export def compile [out: path]: list -> nothing {
  process-positional | typst compile "-" $out
}
