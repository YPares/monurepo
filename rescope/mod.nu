export use ./lib.nu *
export use ./common-resources.nu *

export-env {
  $env.rescope = {
    closure-store-job-id: null
    scopes: []
  }
}
