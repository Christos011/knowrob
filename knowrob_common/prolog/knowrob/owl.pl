/*
  Copyright (C) 2011 Moritz Tenorth, 2016 Daniel Beßler
  All rights reserved.

  Redistribution and use in source and binary forms, with or without
  modification, are permitted provided that the following conditions are met:
      * Redistributions of source code must retain the above copyright
        notice, this list of conditions and the following disclaimer.
      * Redistributions in binary form must reproduce the above copyright
        notice, this list of conditions and the following disclaimer in the
        documentation and/or other materials provided with the distribution.
      * Neither the name of the <organization> nor the
        names of its contributors may be used to endorse or promote products
        derived from this software without specific prior written permission.

  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
  ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
  DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> BE LIABLE FOR ANY
  DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
  (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
  ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

:- module(knowrob_owl,
    [
      owl_compute_individual_of/2,      % ?Resource, ?Description
      owl_compute_has/3,                % ?Subject, ?Predicate, ?Object
      owl_has_prolog/3,
      owl_class_properties/3,           % ?Class, ?Prop, ?Val
      owl_class_properties_some/3,      % ?Class, ?Prop, ?Val
      owl_class_properties_all/3,       % ?Class, ?Prop, ?Val
      owl_class_properties_value/3,     % ?Class, ?Prop, ?Val
      owl_class_properties_nosup/3,     % ?Class, ?Prop, ?Val
      owl_class_properties_transitive_nosup/3, % ?Class, ?Prop, ?Val
      owl_inspect/3,                    % ?Thing, ?P, ?O
      owl_write_readable/1,             % +Resource
      owl_readable/2,                   % +Resource, -Readable
      owl_instance_from_class/2,
      owl_instance_from_class/3,
      owl_list_to_pl/2,
      owl_entity/2,
      create_owl_entity/2,
      owl_run_event/2,
      owl_create_atomic_region/3
    ]).
/** <module> Utilities for handling OWL information in KnowRob.

@author Moritz Tenorth
@author Daniel Beßler
@license BSD
*/

:- use_module(library('semweb/rdf_db')).
:- use_module(library('semweb/rdfs')).
:- use_module(library('semweb/owl')).
:- use_module(library('knowrob/computable')).
:- use_module(library('knowrob/rdfs')).
:- use_module(library('knowrob/transforms')).

:- rdf_meta owl_compute_individual_of(r, t),
            owl_compute_has(r, r, o),
            owl_has_prolog(r, r, ?),
            owl_class_properties(r,r,t),
            owl_class_properties_some(r,r,t),
            owl_class_properties_all(r,r,t),
            owl_class_properties_value(r,r,t),
            owl_class_properties_nosup(r,r,r),
            owl_class_properties_transitive_nosup(r,r,r),
            owl_inspect(r,r,r),
            owl_readable(r,-),
            owl_write_readable(r),
            owl_instance_from_class(r,-),
            owl_instance_from_class(r,t,-),
            owl_list_to_pl(r,t),
            owl_to_pl(r,-),
            pl_to_owl(+,-),
            owl_assert_now(r,r),
            owl_create_atomic_region(r,t,-).

% define holds as meta-predicate and allow the definitions
% to be in different source files
:- meta_predicate owl_instance_from_class(0, ?, ?, ?).
:- multifile owl_instance_from_class/3.

:- rdf_db:rdf_register_ns(knowrob,'http://knowrob.org/kb/knowrob.owl#', [keep(true)]).
:- rdf_db:rdf_register_ns(dul, 'http://www.ontologydesignpatterns.org/ont/dul/DUL.owl#', [keep(true)]).

		 /*******************************
		 *		  ABOX reasoning		*
		 *******************************/

%% owl_computable_db
owl_computable_db(db(rdfs_computable_has,rdfs_instance_of)).

%% owl_compute_individual_of(?Resource, ?Description) is nondet.
%
% True if Resource satisfies Description
% according the the OWL-Description entailment rules,
% with additional computable semantics.
%
% @param Resource OWL resource identifier
% @param Description OWL class description
% 
owl_compute_individual_of(Resource, Description) :-
  owl_computable_db(DB),
  owl_individual_of(Resource, Description, DB).

%% owl_compute_has(?Subject, ?Predicate, ?Object).
%
% True if this relation is specified, or can be deduced using OWL
% inference rules, or computable semantics.
%
% @param Subject OWL resource iri
% @param Predicate Property iri
% @param Object OWL resource iri or datatype value
%
owl_compute_has(S, P, O) :-
  owl_computable_db(DB),
  owl_has(S, P, O, DB).

owl_has_prolog(S,P,Val) :-
  owl_has(S,P,O),
  rdfs_value_prolog(P,O,Val).

		 /*******************************
		 *		  TBOX reasoning		*
		 *******************************/

%% owl_class_properties(?Class, ?Prop, ?Val) is nondet.
%
% Collect all property values of someValuesFrom- and hasValue-restrictions of a class
%
% @param Class Class whose restrictions are being considered
% @param Prop  Property whose restrictions in Class are being considered
% @param Val   Values that appear in a restriction of a superclass of Class on Property
%
owl_class_properties(Class, Prop, Val) :-
  rdfs_individual_of(Class, owl:'Class'), % make sure Class is bound before calling owl_subclass_of
  (owl_class_properties_some(Class, Prop, Val);
   owl_class_properties_value(Class, Prop, Val)).

%% owl_class_properties_some(?Class, ?Prop, ?Val) is nondet.
%
% Collect all property values of someValuesFrom-restrictions of a class
%
% @param Class Class whose restrictions are being considered
% @param Prop  Property whose restrictions in Class are being considered
% @param Val   Values that appear in a restriction of a superclass of Class on Property
%
owl_class_properties_some(Class, Prop, Val) :-         % read directly asserted properties
  owl_class_properties_1_some(Class, Prop, Val).

owl_class_properties_some(Class, Prop, Val) :-         % also consider properties of superclasses
  owl_subclass_of(Class, Super), Class\=Super,
  owl_class_properties_1_some(Super, Prop, Val).

owl_class_properties_1_some(Class, Prop, Val) :-       % read all values for some_values_from restrictions

  ( (nonvar(Class)) -> (owl_direct_subclass_of(Class, Sup)) ; (Sup     = Class)),
  ( (nonvar(Prop))  -> (rdfs_subproperty_of(SubProp, Prop)) ; (SubProp = Prop)),

  owl_restriction(Sup,restriction(SubProp, some_values_from(Val))).

%% owl_class_properties_all(?Class, ?Prop, ?Val) is nondet.
%
% Collect all property values of allValuesFrom-restrictions of a class
%
% @param Class Class whose restrictions are being considered
% @param Prop  Property whose restrictions in Class are being considered
% @param Val   Values that appear in a restriction of a superclass of Class on Property
%
owl_class_properties_all(Class, Prop, Val) :-         % read directly asserted properties
  owl_class_properties_1_all(Class, Prop, Val).

owl_class_properties_all(Class, Prop, Val) :-         % also consider properties of superclasses
  owl_subclass_of(Class, Super), Class\=Super,
  owl_class_properties_1_all(Super, Prop, Val).

owl_class_properties_1_all(Class, Prop, Val) :-       % read all values for all_values_from restrictions

  ( (nonvar(Class)) -> (owl_direct_subclass_of(Class, Sup)) ; (Sup     = Class)),
  ( (nonvar(Prop))  -> (rdfs_subproperty_of(SubProp, Prop)) ; (SubProp = Prop)),

  owl_restriction(Sup,restriction(SubProp, all_values_from(Val))) .

%% owl_class_properties_value(?Class, ?Prop, ?Val) is nondet.
%
% Collect all property values of hasValue-restrictions of a class
%
% @param Class Class whose restrictions are being considered
% @param Prop  Property whose restrictions in Class are being considered
% @param Val   Values that appear in a restriction of a superclass of Class on Property
%
owl_class_properties_value(Class, Prop, Val) :-         % read directly asserted properties
  owl_class_properties_1_value(Class, Prop, Val).

owl_class_properties_value(Class, Prop, Val) :-         % also consider properties of superclasses
  owl_subclass_of(Class, Super), Class\=Super,
  owl_class_properties_1_value(Super, Prop, Val).

owl_class_properties_1_value(Class, Prop, Val) :-       % read all values for has_value restrictions

  ( (nonvar(Class)) -> (owl_direct_subclass_of(Class, Sup)) ; (Sup     = Class)),
  ( (nonvar(Prop))  -> (rdfs_subproperty_of(SubProp, Prop)) ; (SubProp = Prop)),

  owl_restriction(Sup,restriction(SubProp, has_value(Val))) .

%% owl_class_properties_nosup(?Class, ?Prop, ?Val) is nondet.
%
% Version of owl_class_properties without considering super classes
%
% @param Class Class whose restrictions are being considered
% @param Prop  Property whose restrictions in Class are being considered
% @param Val   Values that appear in a restriction of a superclass of Class on Property
%
owl_class_properties_nosup(Class, Prop, Val) :-         % read directly asserted properties
  owl_class_properties_nosup_1(Class, Prop, Val).

% owl_class_properties_nosup(Class, Prop, Val) :-         % do not consider properties of superclasses
%   owl_subclass_of(Class, Super), Class\=Super,
%   owl_class_properties_nosup_1(Super, Prop, Val).

owl_class_properties_nosup_1(Class, Prop, Val) :-
  owl_direct_subclass_of(Class, Sup),
  ( (nonvar(Prop)) -> (rdfs_subproperty_of(SubProp, Prop)) ; (SubProp = Prop)),

  ( owl_restriction(Sup,restriction(SubProp, some_values_from(Val))) ;
    owl_restriction(Sup,restriction(SubProp, has_value(Val))) ).

%% owl_class_properties_transitive_nosup(?Class, ?Prop, ?Val) is nondet.
%
% Transitive cersion of owl_class_properties without considering super classes
%
% @param Class Class whose restrictions are being considered
% @param Prop  Property whose restrictions in Class are being considered
% @param Val   Values that appear in a restriction of a superclass of Class on Property
%
owl_class_properties_transitive_nosup(Class, Prop, SubComp) :-
    owl_class_properties_nosup(Class, Prop, SubComp).
owl_class_properties_transitive_nosup(Class, Prop, SubComp) :-
    owl_class_properties_nosup(Class, Prop, Sub),
    owl_individual_of(Prop, owl:'TransitiveProperty'),
    Sub \= Class,
    owl_class_properties_transitive_nosup(Sub, Prop, SubComp).

%% owl_inspect(?Thing, ?P, ?O).
%
% Read information stored for Thing. Basically a wrapper around owl_has and
% owl_class_properties that aggregates their results. The normal use case is to
% have Thing bound and ask for all property/object pairs for this class or
% individual.
%
% @param Thing  RDF identifier, either an OWL class or an individual
% @param P      OWL property identifier 
% @param O      OWL class, individual or literal value specified as property P of Thing
% 
owl_inspect(Thing, P, O) :-
  rdf_has(Thing, rdf:type, owl:'NamedIndividual'), !,
  owl_has(Thing, P, Olit),
  strip_literal_type(Olit, O).
  
owl_inspect(Thing, P, O) :-
  rdf_has(Thing, rdf:type, owl:'Class'),
  owl_class_properties(Thing, P, Olit),
  strip_literal_type(Olit, O).

		 /*******************************
		 *		  Input-Output			*
		 *******************************/

%% owl_write_readable(+Resource) is semidet.
% 
% Writes human readable description of Resource.
%
% @param Resource OWL resource
%
owl_write_readable(Resource) :- owl_readable(Resource,Readable), write(Readable), !.

%% owl_readable(+Resource, -Readable).
%
% Utility predicate to convert RDF terms into a readable representation.
%
owl_readable(class(Cls),Out) :- owl_readable_internal(Cls,Out), !.
owl_readable(Descr,Out) :-
  (is_list(Descr) -> X=Descr ; Descr=..X),
  findall(Y_, (member(X_,X), once(owl_readable_internal(X_,Y_))), Y),
  Out=Y.
owl_readable_internal(P,P_readable) :-
  atom(P), rdf_has(P, owl:inverseOf, P_inv),
  owl_readable_internal(P_inv, P_inv_),
  atomic_list_concat(['inverse_of(',P_inv_,')'], '', P_readable), !.
owl_readable_internal(class(X),Y) :- atom(X), owl_readable_internal(X,Y).
owl_readable_internal(X,Y) :- atom(X), rdf_split_url(_, Y, X).
owl_readable_internal(X,X) :- atom(X).
owl_readable_internal(X,Y) :- compound(X), owl_readable(X,Y).
owl_readable_internal(X,X).

		 /*******************************
		 *		  Events	*
		 *******************************/

owl_assert_now(TimeInterval, Property) :-
  get_time(CurrentTime),
  term_to_atom(CurrentTime,X),
  rdf_assert(TimeInterval, Property, literal(type(knowrob:double,X))).

owl_event_time_interval(Event, TimeInterval):-
  rdf_has(Event, dul:hasTimeInterval, TimeInterval),!.
owl_event_time_interval(Event, TimeInterval):-
  rdf_instance_from_class(dul:'TimeInterval',TimeInterval),
  rdf_assert(Event, dul:hasTimeInterval, TimeInterval),!.

owl_run_event(Event, Goal) :-
  owl_event_time_interval(Event, TimeInterval),
  setup_call_cleanup(
    owl_assert_now(TimeInterval, ease:hasIntervalBegin),
    call(Goal, Event),
    owl_assert_now(TimeInterval, ease:hasIntervalEnd)
  ).

		 /*******************************
		 *		  converting between OWL / Prolog representation	*
		 *******************************/

owl_list_to_pl(X,[X|Xs]) :-
  rdf_has(Y,dul:follows,X),!,
  owl_list_to_pl(Y,Xs).
owl_list_to_pl(X,[X]).

%% TODO need to handle reified classes & properties here
owl_entity(Arg_owl,Arg_pl) :-
  rdfs_individual_of(Arg_owl,dul:'Collection'),!,
  findall(X, (
    rdf_has(Arg_owl,dul:hasMember,X_owl),
    owl_entity(X_owl,X)),
    Arg_pl).
owl_entity(Arg_owl,Arg_pl) :-
  rdfs_individual_of(Arg_owl,dul:'Region'),
  rdf_has_prolog(Arg_owl,dul:hasDataValue,Arg_pl),!.
owl_entity(Arg_owl,Arg_owl).

%% TODO need to handle reified classes & properties here
create_owl_entity(List,Arg_owl) :-
  is_list(List),!,
  rdf_instance_from_class(dul:'Collection',Arg_owl),
  forall(member(X,List),(
    create_owl_entity(X,X_owl),
    rdf_assert(Arg_owl,dul:hasMember,X_owl)
  )).
create_owl_entity(Iri,Iri) :-
  rdf_has(Iri,_,_),!.
create_owl_entity(literal(type(DataType,Atom)),Arg_owl) :-
  rdf_instance_from_class(dul:'Region',Arg_owl),
  rdf_assert(Arg_owl,dul:hasRegionDataValue,literal(type(DataType,Atom))),!.
create_owl_entity(Atom,Arg_owl) :-
  atom(Atom),
  rdf_instance_from_class(dul:'Region',Arg_owl),
  rdf_assert_prolog(Arg_owl,dul:hasRegionDataValue,Atom),!.

		 /*******************************
		 *		  Some common Prolog->OWL conversions		*
		 *******************************/

%% owl_create_atomic_region(DataType,Value,Region)
%
%
owl_create_atomic_region(DataType, List, Region) :-
  is_list(List),!,
  findall(X, (
    member(Y,List),
    term_to_atom(Y,X)),
    AtomList),
  atomic_list_concat(AtomList, ' ', Atom),
  rdf_instance_from_class(dul:'Region',Region),
  rdf_assert(Region,dul:hasRegionDataValue,literal(type(DataType,Atom))).
%%
owl_create_atomic_region(DataType, String, Region) :-
  string(String),!,
  string_to_atom(String,Atom),
  owl_create_atomic_region(DataType, Atom, Region).
%%
owl_create_atomic_region(DataType, Term, Region) :-
  term_to_atom(Term,Atom),
  rdf_instance_from_class(dul:'Region',Region),
  rdf_assert(Region,dul:hasRegionDataValue,literal(type(DataType,Atom))).

%% owl_create_array(List,Array)
%
%
owl_create_array(List, Array) :- fail. % TODO

		 /*******************************
		 *		  ABOX ASSERTIONS		*
		 *******************************/


%% owl_instance_from_class(+Class, -Instance) is det.
%% owl_instance_from_class(+Class, +ConfigDict, -Instance) is det.
%
% Asserts new instance Instance with rdf:type Class.
%
owl_instance_from_class(Class, Instance) :-
  ( owl_instance_from_class(Class, [], Instance);
    rdf_instance_from_class(Class, Instance)), !.

%%%%%%%%%%%%%%%%%%%
%% knowrob:Pose

owl_instance_from_class('http://knowrob.org/kb/knowrob.owl#Pose', [pose=(Frame,[X,Y,Z],[QW,QX,QY,QZ])], Pose) :- !,
  rdf_unique_id('http://knowrob.org/kb/knowrob.owl#Pose', Pose),
  atomic_list_concat([X,Y,Z], ' ', Translation),
  atomic_list_concat([QW,QX,QY,QZ], ' ', Quaternion),
  rdf_assert(Pose, rdf:type, knowrob:'Pose'),
  rdf_assert(Pose, knowrob:'translation', literal(type(knowrob:vec3,Translation))),
  rdf_assert(Pose, knowrob:'quaternion', literal(type(knowrob:vec4,Quaternion))),
  rdf_assert(Pose, knowrob:'relativeTo', Frame).

owl_instance_from_class('http://knowrob.org/kb/knowrob.owl#Pose', [pose=(Pos,Rot)], Pose) :- !,
  owl_instance_from_class(knowrob:'Pose',
      [pose=(knowrob:'MapFrame', Pos, Rot)], Pose).

owl_instance_from_class('http://knowrob.org/kb/knowrob.owl#Pose', [mat=(Data)], Pose) :- !,
  matrix(Data, Pos, Rot),
  owl_instance_from_class('http://knowrob.org/kb/knowrob.owl#Pose', [pose=(Pos, Rot)], Pose).

owl_instance_from_class('http://knowrob.org/kb/knowrob.owl#Pose', [pose=pose(A,B,C)], Pose) :- !,
  owl_instance_from_class('http://knowrob.org/kb/knowrob.owl#Pose', [pose=(A,B,C)], Pose).

owl_instance_from_class('http://knowrob.org/kb/knowrob.owl#Pose', [pose=pose(A,B)], Pose) :- !,
  owl_instance_from_class('http://knowrob.org/kb/knowrob.owl#Pose', [pose=(A,B)], Pose).

%%%%%%%%%%%%%%%%%%%
%% knowrob:'FrameOfReference'

owl_instance_from_class('http://knowrob.org/kb/knowrob.owl#FrameOfReference', [urdf=Name], Frame) :- !,
  atomic_list_concat(['http://knowrob.org/kb/knowrob.owl#FrameOfReference'|[Name]], '_', Frame),
  rdf_assert(Frame, rdf:type, knowrob:'FrameOfReference'),
  rdf_assert(Frame, 'http://knowrob.org/kb/srdl2-comp.owl#urdfName', literal(type(xsd:string, Name))).

%%%%%%%%%%%%%%%%%%%
%% knowrob:'SpaceRegion'

owl_instance_from_class('http://www.ontologydesignpatterns.org/ont/dul/DUL.owl', [axioms=Axioms], SpaceRegion) :- !,
  location_name_args_(Axioms,Args),
  atomic_list_concat(['http://www.ontologydesignpatterns.org/ont/dul/DUL.owl'|Args], '_', SpaceRegion),
  rdf_assert(SpaceRegion, rdf:type, dul:'Place'),
  forall( member([P,O], Axioms), rdf_assert(SpaceRegion, P, O) ).

location_name_args_([[P,O]|Axioms], [P_name|[O_name|Args]]) :-
  rdf_split_url(_, P_name, P),
  rdf_split_url(_, O_name, O),
  location_name_args_(Axioms, Args).
location_name_args_([], []).
