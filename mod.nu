export use ./lib.nu *
export use ./common-resources.nu *

export-env {
  $env.rescope = {
    scopes: {}
    job: null
    innermost: null
  }
}
