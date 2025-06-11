export use ./lib.nu *
export use ./common-resources.nu *

export-env {
  $env.rescope = {
    job-id: null
    scopes: []
  }
}
