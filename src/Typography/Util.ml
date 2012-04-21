(** Auxiliary functions *)
open CamomileLibrary
open Config

exception File_not_found of (string*string list)
(** Chercher un fichier dans un chemin *)
let findPath f path=
  let rec findPath f=function
      []->raise (File_not_found (f,path))
    | h::s when Sys.file_exists (Filename.concat h f)->(Filename.concat h f)
    | h::s -> (findPath f s)
  in
    findPath f path
(** Chercher un fichier dans le chemin des polices *)
let findFont f=findPath f ("."::(!fontsdir))
(** Chercher un fichier dans le chemin des grammaires *)
let findGrammar f=findPath f ("." :: (!grammarsdir))
(** Chercher un fichier dans le chemin des dictionnaires de césures *)
let findHyph f=findPath f ("."::(!hyphendir))

(** Convertir en points Adobe une longueur en millimètres *)
let pt_of_mm x=(72.*.x)/.25.4
(** Convertir en millimètres une longueur en points Adobe *)
let mm_of_pt x=(25.4*.x)/.72.

let a4=(210.,297.)
let phi=(1.+.(sqrt 5.))/.2.


let readInt f n0=
  let rec readInt_ n x=
    if n=n0 then x else
      readInt_ (n+1) ((x lsl 8) + (input_byte f))
  in
    readInt_ 0 0

let buf=String.create 4

let readInt2 f=
  really_input f buf 0 2;
  let d=((int_of_char buf.[0]) lsl 8) lor (int_of_char buf.[1]) in
    d

let readInt4 f=
  really_input f buf 0 4;
  let a=(int_of_char buf.[0]) lsl 8 in
  let b=(a lor (int_of_char buf.[1])) lsl 8 in
  let c=(b lor (int_of_char buf.[2])) lsl 8 in
  let d=c lor (int_of_char buf.[3]) in
    d


let int16 x=if x<=0x7f then x else x-0x10000

let round x=
  let c=ceil x in
    if (c-.x) < 0.5 && (c-.x)> -0.5 then int_of_float c else
      if c-.x=0.5 || c-.x=(-0.5) then
        if int_of_float (floor x) mod 2=0 then int_of_float (floor x) else int_of_float c
      else
        int_of_float (floor x)

let round_float x=float_of_int (round x)


let rec span f=function
    []->([],[])
  | h::s when f h->let (a,b)=span f s in (h::a, b)
  | l->([],l)

let rec break f=function
    []->([],[])
  | h::s when not (f h)->let (a,b)=break f s in (h::a, b)
  | l->([],l)

let rec take x l=
  if x<=0 then [] else
    match l with
        []->[]
      | h::s->h::(take (x-1) s)

let rec drop x l=
  if x<=0 then l else
    match l with
        []->[]
      | _::s->drop (x-1) s

let rec last=function
    [h]->h
  | _::s->last s
  | _->raise Not_found

let rec init=function
    [_] | [] ->[]
  | h::s->h::init s

let is_space x0=
  let x=UChar.uint_code x0 in
    (x>=0x0009 && x<=0x000d)
  || x=0x0020
  || x=0x00a0
  || x=0x1680
  || x=0x180e
  || (x>=0x2000 && x<=0x200a)
  || x=0x202f
  || x=0x205f
  || x=0x3000

let unspace s=
  let rec rem i j=
    if i>j then "" else
      if is_space (UTF8.get s i) then
        rem (UTF8.next s i) j
      else
        if is_space (UTF8.get s j) then
          rem i (UTF8.prev s j)
        else
          String.sub s i (j-i+1)
  in
    rem (UTF8.first s) (UTF8.last s)


module IntMap=New_map.Make (struct type t=int let compare=compare end)
module StrMap=New_map.Make (String)
module IntSet=Set.Make (struct type t=int let compare=compare end)
