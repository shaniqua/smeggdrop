package require sha1

namespace eval commands {
  proc sha1 string {
    ::sha1::sha1 $string
  }
}
