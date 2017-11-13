(*
 * Copyright (c) 2014 Leo White <lpw25@cl.cam.ac.uk>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *)

type 'a parser

val build : (Xmlm.input -> 'a) -> 'a parser

type 'a result =
  | Ok of 'a
  | Error of Xmlm.pos option * Xmlm.pos * string

val text :
  'a parser -> Xmlm.input -> 'a Doc_model.Types.Documentation.text result

val unit : 'a parser -> Xmlm.input -> 'a Doc_model.Types.Unit.t result
val unit_file : 'a parser -> Xmlm.input -> 'a Doc_model.Types.Unit.t result

val page : 'a parser -> Xmlm.input -> 'a Doc_model.Types.Page.t result
val page_file : 'a parser -> Xmlm.input -> 'a Doc_model.Types.Page.t result
