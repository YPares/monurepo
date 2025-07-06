export def get-matches [
]: string -> record<change_or_op_id?: string, file?: string> {
  let ids_parser = $"(char us)\(?<change_or_op_id>.+)(char us)\(?<commit_id>.*)(char us)"
  let file_parser = $"(char fs)\(?<file>.+)(char fs)"

  let text = $in
  [
    ...($text | parse -r $ids_parser)
    ...($text | parse -r $file_parser)
  ] | into record
}
