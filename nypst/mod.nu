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

# Call a typst function with only positional args
export def pcall [
  fn_name: string
  ...positional_args: any
] {
  call $fn_name {} ...$positional_args
}

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

export def set [
  fn_name: string
  named_args = {}: record
  ...positional_args
] {
  $"set (call $fn_name $named_args ...$positional_args)"
}

# Use set with only positional args
export def pset [
  fn_name: string
  ...positional_args
] {
  set $fn_name {} ...$positional_args
}

export def show [
  pattern: string
  ...args 
] {
  $"show ($pattern): ($args | process-positional --in-code)"
}

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

# TODO: Handle escaping better
export def raw-str [] {
  $"\"($in)\""
}

export def array [...elems] {
  $elems | process-positional --sep ', ' | $"\(($in))"
}

export def compile [out: path] {
  process-positional | typst compile "-" $out
}
