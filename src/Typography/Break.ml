(*
  Copyright Florian Hatat, Tom Hirschowitz, Pierre Hyvernat,
  Pierre-Etienne Meunier, Christophe Raffalli, Guillaume Theyssier 2012.

  This file is part of Patoline.

  Patoline is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Patoline is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with Patoline.  If not, see <http://www.gnu.org/licenses/>.
*)
open Util
open UsualMake
open Box
open FTypes


let is_last paragraph j=
  let rec is_last i=
    (i>=Array.length paragraph ||
       match paragraph.(i) with
           Glue _->is_last (i+1)
         | _->false)
  in
  is_last (j+1)


type figurePosition=Placed of line | Flushed | Begun


module type Line =
  sig
    type t
    val compare : t -> t -> int
    val hash    : t -> int
  end

module Make(L : Line with type t = Box.line) =
  struct
    module LineMap=Map.Make (L)
    module ColMap=Map.Make (
      struct
        type t=float*float*line*float*float*line
        let compare=compare
      end)

    module H=Weak.Make(
      struct
        type t=L.t*float*TypoLanguage.message*parameters*(frame_zipper list)*float*(t option)*(figurePosition IntMap.t)*L.t MarkerMap.t
        let equal (a,_,_,_,_,_,_,_,_) (b,_,_,_,_,_,_,_,_)=(L.compare a b)==0
        let hash (a,_,_,_,_,_,_,_,_)=L.hash a
      end)

    let haut=ref (Array.make 100 Empty)
    let max_haut=ref 0
    let bas=ref (Array.make 100 Empty)
    let max_bas=ref 0
    let writeBox arr i b=
      if i>=Array.length !arr then (
        let tmp= !arr in
        arr:=Array.make ((Array.length !arr)*2) Empty;
        for j=0 to Array.length tmp-1 do
          !arr.(j)<-tmp.(j)
        done);
      !arr.(i)<-b

    let readBox arr i= !arr.(i)

    let rec print_graph file paragraphs graph path=
      let f=open_out file in
      let rec make_path p1 p2=function
          [] | [_]->false
        | (_,h)::(a,h')::s->(p1=h && p2=h') || make_path p1 p2 ((a,h')::s)
      in
      Printf.fprintf f "digraph {\n";
      LineMap.iter (fun k (b,_,_,_,_,a,_,_)->
                      Printf.fprintf f "node_%d_%s_%s_%s [label=\"%d : %d, %d, %d\"];\n"
                        k.paragraph (if k.lineStart>=0 then string_of_int k.lineStart else "x")
                        (if k.lineEnd>=0 then string_of_int k.lineEnd else "x")
                        (if k.hyphenEnd>=0 then string_of_int k.hyphenEnd else "x")

                        k.paragraph k.lineStart k.lineEnd k.hyphenEnd;

                      Printf.fprintf f "node_%d_%s_%s_%s -> node_%d_%s_%s_%s[color=%s, label=\"\"]\n"
                        a.paragraph (if a.lineStart>=0 then string_of_int a.lineStart else "x")
                        (if a.lineEnd>=0 then string_of_int a.lineEnd else "x")
                        (if a.hyphenEnd>=0 then string_of_int a.hyphenEnd else "x")

                        k.paragraph (if k.lineStart>=0 then string_of_int k.lineStart else "x")
                        (if k.lineEnd>=0 then string_of_int k.lineEnd else "x")
                        (if k.hyphenEnd>=0 then string_of_int k.hyphenEnd else "x")

                        (if k.lastFigure<>a.lastFigure then "green" else
                           if make_path a k path then "blue" else "black")
                        (*b k.height-a.height*)
                   ) graph;
      Printf.fprintf f "};\n";
      close_out f

    let typeset ?(initial_line=uselessLine) ~completeLine ~figures ~figure_parameters ~parameters ~new_page ~new_line ~badness ~states paragraphs=
      if Array.length paragraphs=0 && Array.length figures=0 then ([],fst (frame_top initial_line.layout),IntMap.empty,MarkerMap.empty) else begin
      let collide line_haut params_i comp_i line_bas params_j comp_j=

        max_haut:=
          if line_haut.isFigure then
            (let fig=figures.(line_haut.lastFigure) in
             writeBox haut 0 (Drawing { fig with drawing_y1=0.; drawing_y0=fig.drawing_y0-.fig.drawing_y1 }); 1)
          else
            fold_left_line paragraphs
              (fun i b->writeBox haut i b; i+1) 0 line_haut;

        max_bas:=
          if line_bas.isFigure then
            (let fig=figures.(line_bas.lastFigure) in
             writeBox bas 0 (Drawing { fig with drawing_y1=0.; drawing_y0=fig.drawing_y0-.fig.drawing_y1 }); 1)
          else
            fold_left_line paragraphs (fun i b->writeBox bas i b; i+1) 0 line_bas;

        let xi=ref params_i.left_margin in
        let xj=ref params_j.left_margin in
        let rec collide i j max_col=
          let box_i=if i< !max_haut then readBox haut i else Empty in
          let box_j=if j< !max_bas then readBox bas j else Empty in
          (* let _=Graphics.wait_next_event [Graphics.Key_pressed] in *)
          let wi=box_width comp_i box_i in
          let wj=box_width comp_j box_j in
          if !xi +.wi < !xj+. wj && i < !max_haut then (
            let yi=lower_y box_i in
            let yj=if !xi+.wi < !xj then -.infinity else
              upper_y box_j
            in
            (* let x0=if !xi+.wi < !xj then !xi else max !xi !xj in *)
            (* let w0= !xi +. wi -. x0 in *)
            (* Graphics.draw_rect (round (mm*. x0)) (yj0 + round (mm*. yj)) *)
            (*   (round (mm*. (w0))) (yi0 -yj0 + round (mm*. (yi-.yj))); *)
            xi:= !xi+.wi;
            collide (i+1) j (min max_col (yi-.yj))
          ) else if j < !max_bas then (
            let yi=if !xj +. wj < !xi then infinity else
              lower_y box_i
            in
            let yj=upper_y box_j in
            (* let x0=if !xj+.wj < !xi then !xj else max !xi !xj in *)
            (* let w0= !xj +. wj -. x0 in *)
            (* Graphics.draw_rect (round (mm*. x0)) (yj0 + round (mm*. yj)) *)
            (*   (round (mm*. w0)) (yi0 -yj0 + round (mm*. (yi-.yj))); *)
            xj:= !xj+.wj;
            collide i (j+1) (min max_col (yi-.yj))
          ) else max_col
        in
        collide 0 0 infinity
      in


      let colision_cache=ref ColMap.empty in
      let endNode=ref None in

      let first_parameters=parameters.(0)
        paragraphs figures default_params IntMap.empty MarkerMap.empty initial_line initial_line
      in
      let first_line=(initial_line,0.,TypoLanguage.Normal,first_parameters,[],0.,None,IntMap.empty,MarkerMap.empty) in
      let last_todo_line=ref first_line in
      let demerits=H.create (Array.length paragraphs) in


      let rec break allow_impossible todo=
        (* A chaque etape, todo contient le dernier morceau de chemin qu'on a construit dans demerits *)
        if not (LineMap.is_empty todo) then (
          let _,((node,lastBadness,_,lastParameters,lastPages,comp0,lastNode_opt,lastFigures,lastUser) as cur_node)=LineMap.min_binding todo in
          (* print_text_line paragraphs node;flush stderr; *)
          (* Printf.fprintf stderr "allow_impossible : %b\n" allow_impossible;flush stderr; *)
          let todo'=ref (LineMap.remove node todo) in
          (* On commence par chercher la première vraie boite après node *)
          let register node nextNode badness log next_params next_pages comp=
            let nextUser=fold_left_line paragraphs
              (fun u box->match box with
                  Marker uu->MarkerMap.add uu nextNode u
                | _->u) lastUser nextNode
            in
            let add_fig k a m=
              try
                match IntMap.find k m with
                    Placed _->m
                  | _->IntMap.add k a m
              with
                  Not_found -> IntMap.add k a m
            in
            let figures1=fold_left_line paragraphs
              (fun u box->match box with
                  FlushFigure i->add_fig i Flushed u
                | BeginFigure i->add_fig i Begun u
                | _->u) lastFigures nextNode
            in
            let figures2=if nextNode.isFigure then
                IntMap.add nextNode.lastFigure (Placed nextNode) figures1
              else figures1
            in
            let badness=match classify_float badness with FP_infinite | FP_nan -> 0. | _->badness in
            let a=(nextNode,badness,log,next_params,next_pages,comp,node,figures2,nextUser) in
            try
              let _,bad,_,_,_,_,_,_,_=H.find demerits a in
              if allow_impossible || bad >= badness then (
                last_todo_line:=a;
                todo':=LineMap.add nextNode a !todo';
                H.add demerits a
              )
            with Not_found->(
              last_todo_line:=a;
              todo':=LineMap.add nextNode a !todo';
              H.add demerits a
            )
          in
          let register_endNode ()=
            match !endNode with
                Some (_,b,_,_,_,_,_,_,_) when b<lastBadness->()
              | None
              | Some _->endNode:=Some cur_node
          in
          let place_figure ()=
            let fig=figures.(node.lastFigure+1) in
            let vspace,_=
              if node.lineEnd<0 then 0.,0. else
                if node.isFigure then (
                  (figures.(node.lastFigure).drawing_y0,
                   figures.(node.lastFigure).drawing_y1)
                ) else
                  line_height paragraphs figures node
            in
            if node.height+.vspace -. (fig.drawing_y1 -. fig.drawing_y0)
              >=(fst node.layout).frame_y0 then (
              let layouts0,h0=
                if snd node.layout=[] then (
                  let zip=new_page.(node.paragraph) node.layout in
                  let h0=(fst zip).frame_y1 in
                  (* pages:=zip::(!pages); *)
                  zip,h0
                ) else
                  if lastParameters.min_page_after>0 then
                    let rec make_new_pages n zip=if n<=0 then zip else (
                      let zip=new_page.(node.paragraph) zip in
                      (* pages:=zip::(!pages); *)
                      make_new_pages (n-1) zip
                    )
                    in
                    let zip=make_new_pages lastParameters.min_page_after node.layout in
                    let h0=(fst zip).frame_y1 in
                    (zip, h0)
                  else
                    if node.height<(fst node.layout).frame_y0 then (
                      match next_zipper node.layout with
                          None->
                          let a,b=new_page.(node.paragraph) node.layout in
                            (* pages:=(a,b)::(!pages); *)
                            (a,b),a.frame_y1
                        | Some a->a,(fst a).frame_y1
                    ) else
                      (node.layout, node.height)
              in
                let nextNode={
                  paragraph=if node.isFigure then node.paragraph else node.paragraph+1;
                  lastFigure=node.lastFigure+1; isFigure=true;
                  hyphenStart= -1; hyphenEnd= -1;
                  height=h0+.vspace-.fig.drawing_y1;
                  lineStart= -1; lineEnd= -1; paragraph_height= -1;
                  layout=layouts0;
                  page_line=node.page_line+1;
                  min_width=fig.drawing_min_width;
                  nom_width=fig.drawing_nominal_width;
                  max_width=fig.drawing_max_width;
                  line_y0=fig.drawing_y0;line_y1=fig.drawing_y1 }
              in
              let params=figure_parameters.(node.lastFigure+1) paragraphs figures lastParameters lastFigures lastUser node nextNode in
              let next_h=
                (* node.height+.vspace-.fig.drawing_y1 *)
                new_line.(
                  min nextNode.paragraph (Array.length new_line-1)
                ) node lastParameters
                  nextNode params node.layout 0.
              in
              let nextNode={nextNode with height=next_h } in
              register (Some cur_node) nextNode
                (lastBadness+.
                   if node.paragraph<Array.length paragraphs then badness.(node.paragraph) paragraphs figures
                     lastFigures
                     node !haut 0 lastParameters 0.
                     nextNode !bas 0 params 0.
                   else 0.)
                TypoLanguage.Normal
                params
                lastPages
                0.;
            ) else if allow_impossible then (
              let nextNode={
                paragraph=if node.isFigure then node.paragraph else node.paragraph+1;
                lastFigure=node.lastFigure+1; isFigure=true;
                hyphenStart= -1; hyphenEnd= -1;
                height=fig.drawing_y1-.fig.drawing_y0;
                lineStart= -1; lineEnd= -1; paragraph_height= -1;
                page_line=node.page_line+1;
                layout=node.layout;
                min_width=fig.drawing_min_width;
                nom_width=fig.drawing_nominal_width;
                max_width=fig.drawing_max_width;
                line_y0=fig.drawing_y0;
                line_y1=fig.drawing_y1 }
              in
              let params=figure_parameters.(node.lastFigure+1) paragraphs figures lastParameters lastFigures lastUser node nextNode in

              register (Some cur_node) nextNode
                (lastBadness+.
                   if node.paragraph<Array.length paragraphs then badness.(node.paragraph) paragraphs figures
                     lastFigures
                     node !haut 0 lastParameters 0.
                     nextNode !bas 0 params 0.
                   else 0.)
                TypoLanguage.Normal
                params
                lastPages
                0.;
              );
          in

          (* Position in paragraphs to start from. *)
          let i,pi=
            if node.paragraph>=Array.length paragraphs then (0,node.paragraph) else
              if (node.hyphenEnd<0 && node.lineEnd+1>=
                    Array.length paragraphs.(node.paragraph)) then
                (0,node.paragraph+1)
              else if node.hyphenEnd<0 then (node.lineEnd+1, node.paragraph) else
                (node.lineEnd, node.paragraph)
          in

          if pi >= Array.length paragraphs then (
            (* The game is over. Place remaining figures. *)
            if node.lastFigure+1>=Array.length figures then (
              register_endNode ()
            ) else (
              place_figure ()
            );
          ) else (
            (* Move to next nodes. *)
            let flushed=
              (node.lastFigure+1 < Array.length figures) &&
                (try (match IntMap.find (node.lastFigure+1) lastFigures with
                    Flushed ->true
                  | _ ->false)
                 with
                     Not_found ->false)
            in
            if (node.lineEnd+1>=Array.length paragraphs.(node.paragraph) || node.lineEnd<=0)
              && flushed
            then place_figure () else (
              if pi<>node.paragraph then (
                let placable=
                  (node.lastFigure+1 < Array.length figures) &&
                    (IntMap.mem (node.lastFigure+1) lastFigures)
                in
                if placable then place_figure ();
              );
              let pages=ref lastPages in
              let layouts0,h0=
                if snd node.layout=[] then (
                  let zip=new_page.(pi) node.layout in
                  let h0=(fst zip).frame_y1 in
                  pages:=zip::(!pages);
                  zip,h0
                ) else
                  if lastParameters.min_page_after>0 then
                    let rec make_new_pages n zip=if n<=0 then zip else (
                      let zip=new_page.(pi) zip in
                      pages:=zip::(!pages);
                      make_new_pages (n-1) zip
                    )
                    in
                    let zip=make_new_pages lastParameters.min_page_after node.layout in
                    let h0=(fst zip).frame_y1 in
                    (zip, h0)
                  else
                    if node.height<(fst node.layout).frame_y0 then (
                      match next_zipper node.layout with
                          None->
                            let a,b=new_page.(pi) node.layout in
                            pages:=(a,b)::(!pages);
                            (a,b),a.frame_y1
                        | Some a->a,(fst a).frame_y1
                    ) else
                      (node.layout, node.height)
              in
              let local_opt=ref [] in
              let extreme_solutions=ref [] in
              let max_min_page_before=ref 0 in
              let min_min_page_before=ref 0 in

              let rec fix layouts pages_created height n_iter=
                (* Printf.fprintf stderr "%d / %d fix %f\n" (frame_page (List.hd layouts)) n_iter height;flush stderr; *)
                let layout=List.hd layouts in
                let nextNode={
                  paragraph=pi; lastFigure=node.lastFigure; isFigure=false;
                  hyphenStart= node.hyphenEnd; hyphenEnd= (-1);
                  height = height;
                  layout=layout;
                  lineStart= i; lineEnd= i;
                  paragraph_height=if i=0 then 0 else node.paragraph_height+1;
                  page_line=if layout==node.layout then node.page_line+1 else 0;
                  min_width=0.;nom_width=0.;max_width=0.;
                  line_y0=infinity; line_y1= -.infinity }
                in

                if (height<(fst layout).frame_y0) then (
                  let np=new_page.(pi) layout in
                  (* Printf.fprintf stderr "new page\n";flush stderr; *)
                  fix (np::layouts) (pages_created+1) (fst np).frame_y1 (n_iter+1)
                ) else (
                  let make_next_node nextNode=
                    let nextParams=parameters.(pi)
                      paragraphs figures lastParameters lastFigures lastUser node nextNode
                    in
                    let nextLayout=line_layout paragraphs nextNode layout in

                    max_min_page_before:=max !max_min_page_before nextParams.min_page_before;
                    min_min_page_before:=min !min_min_page_before nextParams.min_page_before;
                    if layout_page nextNode>=layout_page node+nextParams.min_page_before then (
                      if (n_iter>= nextParams.min_lines_before &&
                            n_iter>=lastParameters.min_lines_after) ||
                        layout_page nextNode>layout_page node then (
                          let comp1=comp paragraphs nextParams.measure pi i node.hyphenEnd nextNode.lineEnd nextNode.hyphenEnd in
                          let nextNode_width=nextNode.min_width +. comp1*.(nextNode.max_width-.nextNode.min_width) in
                          let height'=
                            if frame_page nextLayout==layout_page node &&
                              (not (node==initial_line)) then (

                          (* Demander à toutes les lignes au-dessus de pousser nextNode le plus bas possible *)
                              let rec v_distance cur_node0 parameters comp0 min_h=
                                let node0,_,_,_,_,_,_,_,_=cur_node0 in
                                if node0.isFigure then (
                                  let fig=figures.(node0.lastFigure) in
                                  min min_h
                                    (node0.height-.(snd (line_height paragraphs figures nextNode))+.fig.drawing_y0)
                                ) else (
                                  (* Hauteur à laquelle devrait être placée nextNode pour ne pas taper sur node0 *)
                                  let max_space = max nextParams.min_height_before parameters.min_height_after in
                                  let h=
                                    node0.height  -. max_space +.
                                       (try
                                          ColMap.find (parameters.left_margin, parameters.measure, { node0 with height=0. },
                                                       nextParams.left_margin, nextParams.measure, { nextNode with height=0. }) !colision_cache
                                        with
                                            Not_found -> (
                                              let dist=collide node0 parameters comp0 nextNode nextParams comp1 in
                                              colision_cache := ColMap.add (parameters.left_margin, parameters.measure,
                                                                            {node0 with height=0.;layout=doc_frame,[]},
                                                                            nextParams.left_margin, nextParams.measure,
                                                                            {nextNode with layout=doc_frame,[];
                                                                              height=0.})
                                                dist !colision_cache;
                                              dist
                                            ))
                                  in
                                  let node0_width=node0.min_width +. comp0*.(node0.max_width-.node0.min_width) in
                                  (try
                                     let _,_,_,_,_,_,prec,_,_=cur_node0 in
                                     let (prec_line,_,_,params,_,comp,_,_,_) as prec_=match prec with None->raise Not_found | Some a->a in
                                     let arret=
                                       (nextParams).left_margin>=parameters.left_margin
                                       && (nextParams).left_margin+.nextNode_width<=parameters.left_margin+.node0_width
                                     in
                                     if prec_line.layout==nextLayout && not arret then (v_distance prec_ params comp (min h min_h)) else
                                       min (min h min_h) (
                                         (node0.height
                                          -. max (snd (line_height paragraphs figures nextNode))
                                            max_space)
                                       )
                                   with
                                       Not_found->
                                         min (min h min_h) (
                                           (node0.height
                                            -. max (snd (line_height paragraphs figures nextNode))
                                              max_space)
                                         )
                                  )
                                )
                              in
                              v_distance cur_node lastParameters comp0 infinity
                            ) else (
                              (fst nextLayout).frame_y1 -. snd (line_height paragraphs figures nextNode);
                            )
                          in
                          let node_is_orphan=
                            (not (nextLayout==node.layout))
                            &&
                              ((node.lineStart = 0
                               && node.lineEnd < Array.length (paragraphs.(node.paragraph))
                               && node.paragraph>0) (* la premiere ligne du document n'est pas orpheline *)
                               || lastParameters.not_last_line)
                            && nextParams.min_page_before<=0
                            && not node.isFigure
                          in
                          let nextNode_is_widow=
                            (not (nextLayout==node.layout))
                            && (not (node==initial_line))
                            &&
                              ((nextNode.lineStart > 0
                                && nextNode.lineEnd >= Array.length (paragraphs.(nextNode.paragraph)))
                               || nextParams.not_first_line)
                            && nextParams.min_page_before<=0
                          in
                          if node_is_orphan then (
                            (* Printf.fprintf stderr "node is orphan\n"; *)
                            if allow_impossible then (
                              try
                                let _,_,_,_,_,_,prec,_,_=cur_node in
                                let pr,a,b,c,d,e,f,g,h=match prec with None->raise Not_found | Some a->a  in
                                if node.paragraph=nextNode.paragraph || (lastParameters.not_last_line && not c.not_last_line) then (
                                  extreme_solutions:=(pr,a,(TypoLanguage.Opt_error (TypoLanguage.Orphan (text_line paragraphs node))),
                                                      { c with min_page_after=1 },
                                                      d,e,f,g,h)::(!extreme_solutions)
                                ) else raise Not_found
                              with
                                  Not_found->(
                                    extreme_solutions:=(nextNode,lastBadness,(TypoLanguage.Opt_error (TypoLanguage.Orphan (text_line paragraphs nextNode))),
                                                        nextParams,layouts,comp1,Some cur_node,lastFigures,lastUser)::(!extreme_solutions)
                                  )
                            )
                          ) else if nextNode_is_widow then (
                            (* Printf.fprintf stderr "nextNode is widow\n"; *)
                            if allow_impossible then (
                              try
                                let _,_,_,_,_,_,prec,_,_=cur_node in
                                let pr,a,b,c,d,e,f,g,h=match prec with None->raise Not_found | Some a->a  in
                                if node.paragraph=nextNode.paragraph || (nextParams.not_first_line) && not lastParameters.not_first_line then (
                                  extreme_solutions:=(pr,a,(TypoLanguage.Opt_error (TypoLanguage.Widow (text_line paragraphs nextNode))),
                                                      { c with min_page_after=1 },
                                                      d,e,f,g,h)::(!extreme_solutions)
                                ) else raise Not_found
                              with
                                  Not_found->(
                                    extreme_solutions:=(nextNode,lastBadness,(TypoLanguage.Opt_error (TypoLanguage.Widow (text_line paragraphs nextNode))),
                                                        nextParams,layouts,comp1,Some cur_node,lastFigures,lastUser)::(!extreme_solutions)
                                  )
                            )
                          )
                            else if nextNode.min_width > (nextParams).measure then (
                              (* Printf.fprintf stderr "nextNode is overfull\n"; *)
                              if allow_impossible then (
                                if (height<=height')  then (
                                  let bad=(lastBadness+.
                                             badness.(nextNode.paragraph) paragraphs figures lastFigures node !haut !max_haut lastParameters comp0
                                             nextNode !bas !max_bas nextParams comp1) in
                                  local_opt:=(nextNode,
                                              max 0. bad,
                                              (TypoLanguage.Opt_error (TypoLanguage.Overfull_line (text_line paragraphs nextNode))),
                                              nextParams,layouts,comp1,Some cur_node,lastFigures,lastUser)::(!local_opt)
                                )
                              )
                            ) else  if nextNode.max_width < (nextParams).measure
                                && (nextNode.lineEnd<Array.length paragraphs.(nextNode.paragraph))
                            then (
                              (* Printf.fprintf stderr "nextNode is underfull\n"; *)
                              if allow_impossible then (
                                if (height<=height') then (
                                  let bad=(lastBadness+.
                                             badness.(nextNode.paragraph) paragraphs figures lastFigures node !haut !max_haut lastParameters comp0
                                             nextNode !bas !max_bas nextParams comp1) in
                                  local_opt:=(nextNode,
                                              max 0. bad,
                                              (TypoLanguage.Opt_error (TypoLanguage.Underfull_line (text_line paragraphs nextNode))),
                                              nextParams,layouts,comp1,Some cur_node,lastFigures,lastUser)::(!local_opt)
                                )
                              )
                            ) else (
                              if (height<=height') then (
                                let bad=(lastBadness+.
                                           badness.(nextNode.paragraph) paragraphs figures
                                           lastFigures node !haut !max_haut lastParameters comp0
                                           nextNode !bas !max_bas nextParams comp1) in
                                if bad<infinity || allow_impossible then
                                  local_opt:=(nextNode,
                                              max 0. bad,TypoLanguage.Normal,
                                              nextParams,layouts,comp1,Some cur_node,lastFigures,lastUser)::(!local_opt)
                              )
                            )
                        )
                    )
                  in
                  let compl=completeLine.(pi) paragraphs figures lastFigures lastUser nextNode allow_impossible in
                  let compl=if compl=[] && allow_impossible then (
                    [{
                      paragraph=pi; lastFigure=node.lastFigure; isFigure=false;
                      hyphenStart= node.hyphenEnd; hyphenEnd= (-1);
                      height = height;
                      lineStart= i; lineEnd= i+1;
                      paragraph_height=if i=0 then 0 else node.paragraph_height+1;
                      page_line=if node.layout==layout then node.page_line+1 else 0;
                      layout=layout;
                      min_width=0.;nom_width=0.;max_width=0.;
                      line_y0=infinity; line_y1= -.infinity }
                    ]
                  ) else compl
                  in
                  List.iter make_next_node (compl);
                  if !local_opt=[] && !extreme_solutions=[] then
                    if pages_created<=1+max lastParameters.min_page_after !max_min_page_before
                    then (
                      if height<(fst layout).frame_y0 || !min_min_page_before>0 then (
                        let np=new_page.(pi) layout in
                        fix (np::layouts) (pages_created+1) (fst np).frame_y1 (n_iter+1)
                      ) else (
                        let next_h=new_line.(pi) node lastParameters
                          node lastParameters layout height
                        in
                        fix layouts
                          pages_created
                          next_h
                          (n_iter+1)
                      )
                    ) else (
                      if allow_impossible then (
                        let nextNode=List.hd compl in
                        let nextParams=parameters.(nextNode.paragraph)
                          paragraphs figures lastParameters lastFigures lastUser node nextNode
                        in
                        extreme_solutions:=
                          (nextNode,
                           lastBadness,
                           (TypoLanguage.Opt_error (TypoLanguage.Overfull_line (text_line paragraphs nextNode))),
                           nextParams,layouts,0.,Some cur_node,lastFigures,lastUser)::[]
                      )
                    )
                )
              in
              (fix !pages 0 h0 0;
               if allow_impossible && !local_opt=[] && !extreme_solutions<>[] then (
                 List.iter (fun (nextNode,bad,log,params,pages,comp,node,figures,user)->
                   let b,_,_=LineMap.split nextNode !todo' in
                   todo':=b
                 ) !extreme_solutions;
                 local_opt:= !extreme_solutions
               );
               if !local_opt <> [] then (
                 let l0=List.sort (fun (_,b0,_,_,_,_,_,_,_) (_,b1,_,_,_,_,_,_,_)->compare b0 b1) !local_opt in
                 let deg=List.fold_left (fun m (_,_,_,p,_,_,_,_,_)->max m p.local_optimization) 0 l0 in
                 let rec register_list i l=
                   if i>0 || deg<=0 then (
                     match l with
                         []->()
                       | (nextNode,bad,log,params,pages,comp,node,fig,user)::s->(
                         register node nextNode bad log params pages comp;
                         register_list (i-1) s
                       )
                   )
                 in
                 register_list deg l0
               )
              )
            );
          );
          break false !todo'
        )
      in

      let last_failure=ref LineMap.empty in

      let todo0=LineMap.singleton initial_line first_line in
      let r_todo=ref todo0 in
      let finished=ref false in
      let allow_impossible=ref false in
      while not !finished do
        break !allow_impossible !r_todo;
        if !endNode=None then (
          let (b,bad,_,param,pages,comp,node,fig,user)= !last_todo_line in
          try
            let param0=LineMap.find b !last_failure in
            if param0.min_page_after<>param.min_page_after then raise Not_found;
            Printf.fprintf stderr "%s\n" (
              TypoLanguage.message (TypoLanguage.No_solution (text_line paragraphs b)));
            finished:=true
          with
              Not_found->(
                last_failure:=LineMap.add b param !last_failure;
                r_todo:=LineMap.singleton b !last_todo_line;
                allow_impossible:=true;
              )
        ) else finished:=true
      done;

      let (n0,_,_,_,layouts,_,_,figs0,user0) as node0=
        match !endNode with
            None-> !last_todo_line
          | Some x->x
      in
      try
        let rec add_content fr0 path cont=
          (* fr0 est le mec final qu'on va renvoyer *)
          match path with
              []->{ fr0 with frame_content=cont::fr0.frame_content }
            | (h,_)::s->
              { fr0 with
                frame_children=IntMap.add h
                  (add_content
                     (try IntMap.find h fr0.frame_children with Not_found->empty_frame)
                     s cont)
                  fr0.frame_children
              }
        in
        (* Remonter jusqu'en haut *)
        let rec makeParagraphs log node frame=
          let n0,_,log_,params',_,_,next,_,_=node in
          match next with
              None->log,frame
            | Some n->(
              makeParagraphs (match log_ with TypoLanguage.Normal -> log | _->log_::log)
                n
                (add_content frame
                   (match snd n0.layout with []->[] | _::s->s)
                   (Placed_line { line_params=params'; line=n0 }))
            )
        in
        let layout=
          let n0,_,_,_,_,_,_,_,_=node0 in
          (fst (frame_top n0.layout))
        in
        let log,pages=makeParagraphs [] node0 layout in
        (log, pages, figs0,user0)
      with
          Not_found ->
            if Array.length paragraphs=0 && Array.length figures=0 then
              ([],empty_frame,IntMap.empty,MarkerMap.empty)
            else (
              Printf.fprintf stderr "%s" (TypoLanguage.message (TypoLanguage.No_solution ""));
              [],empty_frame,IntMap.empty,MarkerMap.empty
            )
      end
  end
