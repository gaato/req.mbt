// The human-facing entry point of the gaato HTTP stack: depends on
// gaato/http-async so `Client::new()` needs no setup, and on gaato/http and
// gaato/sdk-runtime for the vocabulary and the multipart encoder.

name = "gaato/req"

version = "0.1.0"

license = "Apache-2.0"

readme = "README.md"

repository = "https://github.com/gaato/req.mbt"

keywords = [ "http", "client", "requests", "async" ]

description = "A human-facing async HTTP client for MoonBit: verb functions, a client with defaults, body encoders, responses as values, and a step chain around a swappable transport."

source = "src"

preferred_target = "native"

import {
  "gaato/http@0.2.1",
  "gaato/http-async@0.2.1",
  "gaato/sdk-runtime@0.3.1",
  "moonbitlang/async@0.22.5",
}
