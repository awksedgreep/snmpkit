%%
%% Elixir-compatible SNMP MIB Grammar
%% Based on Erlang/OTP snmpc_mib_gram.yrl
%%

Expect 2.

%% ----------------------------------------------------------------------
Nonterminals 
%% ----------------------------------------------------------------------
accessv1
definition
defvalpart
description
descriptionfield
displaypart
entry
namedbits
fatherobjectname
fieldname
fields
implies
import
import_stuff
imports
imports_from_one_mib
index
indexpartv1
indextypev1
indextypesv1
parentintegers
listofdefinitions
listofimports
mib
mibname
nameassign
newtype
newtypename
objectidentifier
objectname
objecttypev1
prodrel
range_num
referpart
size
sizedescr
statusv1
syntax
tableentrydefinition
traptype
type
usertype
variables
varpart
exports
exportlist
export_stuff

%v2
moduleidentity
revisionpart
revisions
listofdefinitionsv2
mibid
last_updated
organization
contact_info
revision
revision_string
revision_desc
v1orv2
objectidentity
objecttypev2
unitspart
indexpartv2
indextypesv2
indextypev2
statusv2
accessv2
notification
objectspart
objects
definitionv2
textualconvention
objectgroup
notificationgroup
modulecompliance
mc_modulepart
mc_modules
mc_module
mc_modulenamepart
mc_mandatorypart
mc_compliancepart
mc_compliances
mc_compliance
mc_compliancegroup
mc_object
mc_accesspart
agentcapabilities
ac_status
ac_modulepart
ac_modules
ac_module
ac_modulenamepart
ac_variationpart
ac_variations
ac_variation
ac_accesspart
ac_access
ac_creationpart
syntaxpart
writesyntaxpart
fsyntax
defbitsvalue
defbitsnames
macrodefinition
anytokens
anytoken
choiceelements
choiceelement
.

%% ----------------------------------------------------------------------
Terminals 
%% ----------------------------------------------------------------------
integer variable atom string quote '{' '}' '::=' ':' '=' ',' '.' '(' ')' ';' '|' '..' '[' ']'
'ACCESS'
'BEGIN'
'BIT'
'Counter'
'DEFINITIONS'
'DEFVAL'
'DESCRIPTION'
'DISPLAY-HINT'
'END'
'ENTERPRISE'
'EXPORTS'
'FROM'
'Gauge'
'IDENTIFIER'
'IMPORTS'
'INDEX'
'INTEGER'
'MACRO'
'IpAddress'
'NetworkAddress'
'OBJECT'
'OBJECT-TYPE'
'OCTET'
'OF'
'Opaque'
'REFERENCE'
'SEQUENCE'
'SIZE'
'STATUS'
'STRING'
'SYNTAX'
'TRAP-TYPE'
'TimeTicks'
'VARIABLES'
'current'
'deprecated'
'obsolete'
'mandatory'
'optional'
'read-only'
'read-write'
'write-only'
'not-accessible'
'accessible-for-notify'
'read-create'

%v2
'LAST-UPDATED'
'ORGANIZATION'
'CONTACT-INFO'
'MODULE-IDENTITY'
'NOTIFICATION-TYPE'
'PRODUCT-RELEASE'
'AGENT-CAPABILITIES'
'INCLUDES'
'SUPPORTS'
'VARIATION'
'CREATION-REQUIRES'
'MODULE-COMPLIANCE'
'OBJECT-GROUP'
'NOTIFICATION-GROUP'
'REVISION'
'OBJECT-IDENTITY'
'MAX-ACCESS'
'UNITS'
'AUGMENTS'
'IMPLIED'
'OBJECTS'
'TEXTUAL-CONVENTION'
'NOTIFICATIONS'
'MODULE'
'MANDATORY-GROUPS'
'GROUP'
'WRITE-SYNTAX'
'MIN-ACCESS'
'BITS'
'DisplayString' 
'PhysAddress' 
'MacAddress' 
'TruthValue' 
'TestAndIncr' 
'AutonomousType' 
'InstancePointer' 
'VariablePointer' 
'RowPointer' 
'RowStatus' 
'TimeStamp' 
'TimeInterval' 
'DateAndTime' 
'StorageType' 
'TDomain' 
'TAddress'
'Counter32'
'Counter64'
'Gauge32'
'Unsigned32'
'Integer32'
'NULL'
% Additional terminals for macro content
'TYPE'
'NOTATION'
'VALUE'
% ASN.1 syntax terminals
'CHOICE'
'APPLICATION'
'IMPLICIT'
.


Rootsymbol mib.
Endsymbol '$end'.

% **********************************************************************

mib -> mibname 'DEFINITIONS' implies 'BEGIN'
       exports import v1orv2 'END' 
    : {Version, Defs} = '$7',
      {pdata, Version, '$1', '$5', '$6', Defs}.

v1orv2 -> moduleidentity listofdefinitionsv2 :
		  {v2_mib, ['$1'|lreverse(v1orv2_mod, '$2')]}.
v1orv2 -> listofdefinitions : {v1_mib, lreverse(v1orv2_list, '$1')}.

definition -> objectidentifier : '$1'.
definition -> objecttypev1 : '$1'.
definition -> newtype : '$1'.
definition -> tableentrydefinition : '$1'.
definition -> traptype : '$1'.
definition -> macrodefinition : '$1'.
% Support SNMPv2 constructs in v1 MIBs
definition -> textualconvention : '$1'.
definition -> objectidentity : '$1'.
definition -> objecttypev2 : '$1'.
definition -> notification : '$1'.
definition -> objectgroup : '$1'.
definition -> notificationgroup : '$1'.
definition -> modulecompliance : '$1'.
definition -> agentcapabilities : '$1'.

listofdefinitions -> definition : ['$1'] .
listofdefinitions -> listofdefinitions definition : ['$2' | '$1'].

exports -> '$empty' : [].
exports -> 'EXPORTS' exportlist ';' :
           '$2'.

exportlist -> '$empty' : [].
exportlist -> export_stuff : ['$1'].
exportlist -> exportlist ',' export_stuff : ['$3' | '$1'].

export_stuff -> variable : {type, val('$1')}.
export_stuff -> atom : {node, val('$1')}.
export_stuff -> 'OBJECT-TYPE' : {builtin, 'OBJECT-TYPE'}.
export_stuff -> 'NetworkAddress' : {builtin, 'NetworkAddress'}.
export_stuff -> 'IpAddress' : {builtin, 'IpAddress'}.
export_stuff -> 'Counter' : {builtin, 'Counter'}.
export_stuff -> 'Gauge' : {builtin, 'Gauge'}.
export_stuff -> 'TimeTicks' : {builtin, 'TimeTicks'}.
export_stuff -> 'Opaque' : {builtin, 'Opaque'}.

import -> '$empty' : [].
import -> 'IMPORTS' imports ';' : 
          '$2'.

imports -> imports_from_one_mib : 
           ['$1'].
imports -> imports_from_one_mib imports : 
           ['$1' | '$2'].

imports_from_one_mib -> listofimports 'FROM' variable :
                        {{val('$3'), lreverse(imports_from_one_mib, '$1')}, line_of('$2')}.

listofimports -> import_stuff : 
                 ['$1'].
listofimports -> listofimports ',' import_stuff : 
                 ['$3' | '$1'].

import_stuff -> 'OBJECT-TYPE' : {builtin, 'OBJECT-TYPE'}.
import_stuff -> 'TRAP-TYPE' : {builtin, 'TRAP-TYPE'}.
import_stuff -> 'NetworkAddress' : {builtin, 'NetworkAddress'}.
import_stuff -> 'TimeTicks' : {builtin, 'TimeTicks'}.
import_stuff -> 'IpAddress' : {builtin, 'IpAddress'}.
import_stuff -> 'Counter' : {builtin, 'Counter'}.
import_stuff -> 'Gauge' : {builtin, 'Gauge'}.
import_stuff -> 'Opaque' : {builtin, 'Opaque'}.
import_stuff -> variable : {type, val('$1')}.
import_stuff -> atom : {node, val('$1')}.
%v2
import_stuff -> 'MODULE-IDENTITY' : {builtin, 'MODULE-IDENTITY'}.
import_stuff -> 'NOTIFICATION-TYPE' : {builtin, 'NOTIFICATION-TYPE'}.
import_stuff -> 'AGENT-CAPABILITIES' : {builtin, 'AGENT-CAPABILITIES'}.
import_stuff -> 'MODULE-COMPLIANCE' : {builtin, 'MODULE-COMPLIANCE'}.
import_stuff -> 'NOTIFICATION-GROUP' : {builtin, 'NOTIFICATION-GROUP'}.
import_stuff -> 'OBJECT-GROUP' : {builtin, 'OBJECT-GROUP'}.
import_stuff -> 'OBJECT-IDENTITY' : {builtin, 'OBJECT-IDENTITY'}.
import_stuff -> 'TEXTUAL-CONVENTION' : {builtin, 'TEXTUAL-CONVENTION'}.
import_stuff -> 'DisplayString' : {builtin, 'DisplayString'}.
import_stuff -> 'PhysAddress' : {builtin, 'PhysAddress'}.
import_stuff -> 'MacAddress' : {builtin, 'MacAddress'}.
import_stuff -> 'TruthValue' : {builtin, 'TruthValue'}.
import_stuff -> 'TestAndIncr' : {builtin, 'TestAndIncr'}.
import_stuff -> 'AutonomousType' : {builtin, 'AutonomousType'}.
import_stuff -> 'InstancePointer' : {builtin, 'InstancePointer'}.
import_stuff -> 'VariablePointer' : {builtin, 'VariablePointer'}.
import_stuff -> 'RowPointer' : {builtin, 'RowPointer'}.
import_stuff -> 'RowStatus' : {builtin, 'RowStatus'}.
import_stuff -> 'TimeStamp' : {builtin, 'TimeStamp'}.
import_stuff -> 'TimeInterval' : {builtin, 'TimeInterval'}.
import_stuff -> 'DateAndTime' : {builtin, 'DateAndTime'}.
import_stuff -> 'StorageType' : {builtin, 'StorageType'}.
import_stuff -> 'TDomain' : {builtin, 'TDomain'}.
import_stuff -> 'TAddress' : {builtin, 'TAddress'}.
import_stuff -> 'BITS' : {builtin, 'BITS'}.
import_stuff -> 'Counter32' : {builtin, 'Counter32'}.
import_stuff -> 'Counter64' : {builtin, 'Counter64'}.
import_stuff -> 'Gauge32' : {builtin, 'Gauge32'}.
import_stuff -> 'Unsigned32' : {builtin, 'Unsigned32'}.
import_stuff -> 'Integer32' : {builtin, 'Integer32'}.

traptype -> objectname 'TRAP-TYPE' 'ENTERPRISE' objectname varpart
	    description referpart implies integer :
            Trap = make_trap('$1', '$4', lreverse(traptype, '$5'), 
                             '$6', '$7', val('$9')),
            {Trap, line_of('$2')}.

% defines a name to an internal node.
objectidentifier -> objectname 'OBJECT' 'IDENTIFIER' nameassign : 
		    {Parent, SubIndex} = '$4',
                    Int = make_internal('$1', dummy, Parent, SubIndex),
		    {Int, line_of('$2')}.

% defines name, access and type for a variable.
objecttypev1 ->	objectname 'OBJECT-TYPE' 
		'SYNTAX' syntax
               	'ACCESS' accessv1
		'STATUS' statusv1
                'DESCRIPTION' descriptionfield
		referpart indexpartv1 defvalpart
		nameassign : 
                Kind = kind('$13', '$12'),
                OT = make_object_type('$1', '$4', '$6', '$8', '$10', 
                                      '$11', Kind, '$14'),
                {OT, line_of('$2')}.

newtype -> newtypename implies syntax :
           NT = make_new_type('$1', dummy, '$3'),
           {NT, line_of('$2')}.

tableentrydefinition -> newtypename implies 'SEQUENCE' '{' fields '}' : 
                        Seq = make_sequence('$1', lreverse(tableentrydefinition, '$5')),
                        {Seq, line_of('$3')}.

% returns: list of {<fieldname>, <asn1_type>}
fields -> fieldname fsyntax : 
	[{val('$1'), '$2'}].

fields -> fields ',' fieldname fsyntax :  [{val('$3'), '$4'} | '$1'].

fsyntax -> 'BITS' : {{bits,[{dummy,0}]},line_of('$1')}.
fsyntax -> syntax : '$1'.

fieldname -> atom : '$1'.

syntax -> usertype : {{type, val('$1')}, line_of('$1')}.
syntax -> type : {{type, cat('$1')},line_of('$1')}.
syntax -> type size : {{type_with_size, cat('$1'), '$2'},line_of('$1')}.
syntax -> usertype size : {{type_with_size,val('$1'), '$2'},line_of('$1')}.
syntax -> 'INTEGER' '{' namedbits '}' : 
          {{type_with_enum, 'INTEGER', '$3'}, line_of('$1')}.
syntax -> 'BITS' '{' namedbits '}' : 
          {{bits, '$3'}, line_of('$1')}.
syntax -> usertype '{' namedbits '}' :
          {{type_with_enum, 'INTEGER', '$3'}, line_of('$1')}.
syntax -> 'SEQUENCE' 'OF' usertype : 
          {{sequence_of,val('$3')},line_of('$1')}.
syntax -> 'CHOICE' '{' choiceelements '}' : 
          {{choice, '$3'}, line_of('$1')}.
syntax -> '[' 'APPLICATION' integer ']' 'IMPLICIT' syntax : 
          {{tagged_type, 'APPLICATION', val('$3'), 'IMPLICIT', '$6'}, line_of('$1')}.
syntax -> '[' 'APPLICATION' integer ']' syntax : 
          {{tagged_type, 'APPLICATION', val('$3'), undefined, '$5'}, line_of('$1')}.

size -> '(' sizedescr ')' : make_range('$2').
size -> '(' 'SIZE' '(' sizedescr  ')' ')' : make_range('$4').

%% Returns a list of integers describing a range.
sizedescr -> range_num '.' '.' range_num : ['$1', '$4'].
sizedescr -> range_num '..' range_num : ['$1', '$3'].
sizedescr -> range_num '.' '.' range_num sizedescr :['$1', '$4' |'$5'].
sizedescr -> range_num '..' range_num sizedescr :['$1', '$3' |'$4'].
sizedescr -> range_num : ['$1'].
sizedescr -> sizedescr '|' sizedescr : ['$1', '$3'].

range_num -> integer : val('$1') .
range_num -> quote atom  : make_range_integer(val('$1'), val('$2')) . 
range_num -> quote variable  : make_range_integer(val('$1'), val('$2')) .

namedbits -> atom '(' integer ')' : [{val('$1'), val('$3')}].
namedbits -> namedbits ',' atom '(' integer ')' :
		 [{val('$3'), val('$5')} | '$1'].

usertype -> variable : '$1'.

type -> 'OCTET' 'STRING' : {'OCTET STRING', line_of('$1')}.
type -> 'BIT' 'STRING' : {'BIT STRING', line_of('$1')}.
type -> 'OBJECT' 'IDENTIFIER' : {'OBJECT IDENTIFIER', line_of('$1')}.
type -> 'INTEGER' : '$1'.
type -> 'NetworkAddress' : '$1'.
type -> 'IpAddress' : '$1'.
type -> 'Counter' : '$1'.
type -> 'Gauge' : '$1'.
type -> 'TimeTicks' : '$1'.
type -> 'Opaque' : '$1'.
type -> 'DisplayString' : '$1'.
type -> 'PhysAddress' : '$1'.
type -> 'MacAddress' : '$1'.
type -> 'TruthValue' : '$1'.
type -> 'TestAndIncr' : '$1'.
type -> 'AutonomousType' : '$1'.
type -> 'InstancePointer' : '$1'.
type -> 'VariablePointer' : '$1'.
type -> 'RowPointer' : '$1'.
type -> 'RowStatus' : '$1'.
type -> 'TimeStamp' : '$1'.
type -> 'TimeInterval' : '$1'.
type -> 'DateAndTime' : '$1'.
type -> 'StorageType' : '$1'.
type -> 'TDomain' : '$1'.
type -> 'TAddress' : '$1'.
type -> 'Counter32' : '$1'.
type -> 'Counter64' : '$1'.
type -> 'Gauge32' : '$1'.
type -> 'Unsigned32' : '$1'.
type -> 'Integer32' : '$1'.
type -> 'NULL' : '$1'.

% Returns: {FatherName, SubIndex}   (the parent)
nameassign -> implies '{' fatherobjectname parentintegers '}' : {'$3', '$4' }.
nameassign -> implies '{' parentintegers '}' : { root, '$3'}.


varpart -> '$empty' : [].
varpart -> 'VARIABLES' '{' variables '}' : '$3'.
variables -> objectname : ['$1'].
variables -> variables ',' objectname : ['$3' | '$1'].

implies -> '::=' : '$1'.
implies -> ':' ':' '=' : '$1'.
descriptionfield -> string : val('$1').
descriptionfield -> '$empty' : undefined.
description -> 'DESCRIPTION' string : val('$2').
description -> '$empty' : undefined.

displaypart -> 'DISPLAY-HINT' string : display_hint('$2') .
displaypart -> '$empty' : undefined .

% returns: {indexes, undefined} 
%        | {indexes, IndexList} where IndexList is a list of aliasnames.
indexpartv1 -> 'INDEX' '{' indextypesv1 '}' : {indexes, lreverse(indexpartv1, '$3')}.
indexpartv1 -> '$empty' : {indexes, undefined}.

indextypesv1 -> indextypev1 : ['$1'].
indextypesv1 -> indextypesv1 ',' indextypev1 : ['$3' | '$1'].

indextypev1 ->  index : '$1'.

index -> objectname : '$1'.

parentintegers -> integer : [val('$1')].
parentintegers -> atom '(' integer ')' : [val('$3')].
parentintegers -> integer parentintegers : [val('$1') | '$2'].
parentintegers -> atom '(' integer ')' parentintegers : [val('$3') | '$5'].

defvalpart -> 'DEFVAL' '{' integer '}' : {defval, val('$3')}.
defvalpart -> 'DEFVAL' '{' atom '}' : {defval, val('$3')}.
defvalpart -> 'DEFVAL' '{' '{' defbitsvalue '}' '}' : {defval, '$4'}.
defvalpart -> 'DEFVAL' '{' quote atom '}' : 
	      {defval, make_defval_for_string(line_of('$1'), 
			      lreverse(defvalpart_quote_atom, val('$3')),
			      val('$4'))}.
defvalpart -> 'DEFVAL' '{' quote variable '}' : 
	      {defval, make_defval_for_string(line_of('$1'), 
			      lreverse(defvalpart_quote_variable, val('$3')),
			      val('$4'))}.
defvalpart -> 'DEFVAL' '{' string '}' : 
	      {defval, val('$3')}.
defvalpart -> '$empty' : undefined.

defbitsvalue -> defbitsnames : '$1'.
defbitsvalue -> '$empty' : [].

defbitsnames -> atom  : [val('$1')].
defbitsnames -> defbitsnames ',' atom  : [val('$3') | '$1'].

objectname -> atom : val('$1').
mibname -> variable : val('$1').
fatherobjectname -> objectname : '$1'.
newtypename -> variable : val('$1').
newtypename -> 'Integer32' : 'Integer32'.
newtypename -> 'Unsigned32' : 'Unsigned32'.
newtypename -> 'Counter32' : 'Counter32'.
newtypename -> 'Counter64' : 'Counter64'.
newtypename -> 'Gauge32' : 'Gauge32'.
newtypename -> 'IpAddress' : 'IpAddress'.
newtypename -> 'NetworkAddress' : 'NetworkAddress'.
newtypename -> 'Opaque' : 'Opaque'.
newtypename -> 'TimeTicks' : 'TimeTicks'.

accessv1 -> atom: accessv1('$1').
accessv1 -> 'read-only' : 'read-only'.
accessv1 -> 'read-write' : 'read-write'.
accessv1 -> 'write-only' : 'write-only'.
accessv1 -> 'not-accessible' : 'not-accessible'.

statusv1 -> atom : statusv1('$1').
statusv1 -> 'mandatory' : mandatory.
statusv1 -> 'optional' : optional.
statusv1 -> 'obsolete' : obsolete.
statusv1 -> 'deprecated' : deprecated.

referpart -> 'REFERENCE' string : val('$2').
referpart -> '$empty' : undefined.


%%----------------------------------------------------------------------
%% SNMPv2 grammatics
%%v2
%%----------------------------------------------------------------------
moduleidentity -> mibid 'MODULE-IDENTITY' 
                  'LAST-UPDATED' last_updated
	          'ORGANIZATION' organization
                  'CONTACT-INFO' contact_info
	          'DESCRIPTION' descriptionfield 
                  revisionpart nameassign : 
                  MI = make_module_identity('$1', '$4', '$6', '$8', 
                                            '$10', '$11', '$12'), 
                  {MI, line_of('$2')}.

mibid -> atom : val('$1').
last_updated -> string : val('$1') .
organization -> string : val('$1') .
contact_info -> string : val('$1') .

revisionpart -> '$empty' : [] .
revisionpart -> revisions : lreverse(revisionpart, '$1') .

revisions -> revision : ['$1'] .
revisions -> revisions revision : ['$2' | '$1'] .
revision -> 'REVISION' revision_string 'DESCRIPTION' revision_desc : 
            make_revision('$2', '$4') .

revision_string -> string : val('$1') .
revision_desc   -> string : val('$1') .

definitionv2 -> objectidentifier : '$1'.
definitionv2 -> objecttypev2 : '$1'.
definitionv2 -> textualconvention : '$1'.
definitionv2 -> objectidentity : '$1'.
definitionv2 -> newtype : '$1'.
definitionv2 -> tableentrydefinition : '$1'.
definitionv2 -> notification : '$1'.
definitionv2 -> objectgroup : '$1'.
definitionv2 -> notificationgroup : '$1'.
definitionv2 -> modulecompliance : '$1'.
definitionv2 -> agentcapabilities : '$1'.

listofdefinitionsv2 -> '$empty' : [] .
listofdefinitionsv2 -> listofdefinitionsv2 definitionv2 : ['$2' | '$1'].

textualconvention -> newtypename implies 'TEXTUAL-CONVENTION' displaypart
                     'STATUS' statusv2 description referpart 'SYNTAX' syntax :
                     NT = make_new_type('$1', 'TEXTUAL-CONVENTION', '$4', 
                                        '$6', '$7', '$8', '$10'),
                     {NT, line_of('$3')}.
% Alternative rule for complex TEXTUAL-CONVENTION with large enumerations
textualconvention -> newtypename implies 'TEXTUAL-CONVENTION' displaypart
                     'STATUS' statusv2 description referpart 'SYNTAX' 'INTEGER' '{' anytokens '}' :
                     NT = make_new_type('$1', 'TEXTUAL-CONVENTION', '$4', 
                                        '$6', '$7', '$8', {integer_enum, '$11'}),
                     {NT, line_of('$3')}.

objectidentity -> objectname 'OBJECT-IDENTITY' 'STATUS' statusv2
                  'DESCRIPTION' string referpart nameassign : 
                  {Parent, SubIndex} = '$8',
                  Int = make_internal('$1', 'OBJECT-IDENTITY', 
                                      Parent, SubIndex),
                  {Int, line_of('$2')}.

objectgroup -> objectname 'OBJECT-GROUP' objectspart 
               'STATUS' statusv2 description referpart nameassign :
               OG = make_object_group('$1', '$3', '$5', '$6', '$7', '$8'),
	       {OG, line_of('$2')}.

notificationgroup -> objectname 'NOTIFICATION-GROUP' 'NOTIFICATIONS' '{'
                     objects '}' 'STATUS' statusv2 description referpart 
                     nameassign :
                     NG = make_notification_group('$1', '$5', '$8', '$9',
                                                  '$10', '$11'),
                     {NG, line_of('$2')}.

modulecompliance -> objectname 'MODULE-COMPLIANCE' 'STATUS' statusv2
                    description referpart mc_modulepart nameassign : 
                    MC = make_module_compliance('$1', '$4', '$5', '$6', 
                                                '$7', '$8'),
                    {MC, line_of('$2')}.


agentcapabilities -> objectname 'AGENT-CAPABILITIES' 
                     'PRODUCT-RELEASE' prodrel 
                     'STATUS' ac_status
                     description referpart ac_modulepart nameassign : 
                     AC = make_agent_capabilities('$1', '$4', '$6', '$7', 
                                                  '$8', '$9', '$10'),
                     {AC, line_of('$2')}.

prodrel -> string : val('$1').

ac_status -> atom : ac_status('$1').

ac_modulepart -> ac_modules : 
                 lreverse(ac_modulepart, '$1').
ac_modulepart -> '$empty' : 
                 [].

ac_modules -> ac_module : 
              ['$1'].
ac_modules -> ac_module ac_modules : 
              ['$1' | '$2'].

ac_module -> 'SUPPORTS' ac_modulenamepart 'INCLUDES' '{' objects '}' ac_variationpart : 
             make_ac_module('$2', '$5', '$7').

ac_modulenamepart -> mibname : '$1'.
ac_modulenamepart -> '$empty' : undefined.
    
ac_variationpart -> '$empty' : 
                    [].
ac_variationpart -> ac_variations : 
                    lreverse(ac_variationpart, '$1').

ac_variations -> ac_variation : 
                 ['$1'].
ac_variations -> ac_variation ac_variations : 
                 ['$1' | '$2'].

ac_variation -> 'VARIATION' objectname syntaxpart writesyntaxpart ac_accesspart ac_creationpart defvalpart description : 
                 make_ac_variation('$2', '$3', '$4', '$5', '$6', '$7', '$8').

ac_accesspart -> 'ACCESS' ac_access : '$2'.
ac_accesspart -> '$empty' : undefined. 

ac_access -> atom: ac_access('$1').     

ac_creationpart -> 'CREATION-REQUIRES' '{' objects '}' : 
                   lreverse(ac_creationpart, '$3').
ac_creationpart -> '$empty'                            : 
                   []. 

mc_modulepart -> '$empty'   : 
                 [].
mc_modulepart -> mc_modules : 
                 lreverse(mc_modulepart, '$1').

mc_modules -> mc_module : 
              ['$1'].
mc_modules -> mc_module mc_modules : 
              ['$1' | '$2'].
    
mc_module -> 'MODULE' mc_modulenamepart mc_mandatorypart mc_compliancepart : 
             make_mc_module('$2', '$3', '$4').

mc_modulenamepart -> mibname : '$1'.
mc_modulenamepart -> '$empty' : undefined.

mc_mandatorypart -> 'MANDATORY-GROUPS' '{' objects '}' : 
                    lreverse(mc_mandatorypart, '$3').
mc_mandatorypart -> '$empty' : 
                    [].
    
mc_compliancepart -> mc_compliances : 
                     lreverse(mc_compliancepart, '$1').
mc_compliancepart -> '$empty'       : 
                     [].

mc_compliances -> mc_compliance : 
                  ['$1'].
mc_compliances -> mc_compliance mc_compliances : 
                  ['$1' | '$2'].

mc_compliance -> mc_compliancegroup : 
                 '$1'.
mc_compliance -> mc_object          : 
                 '$1'.

mc_compliancegroup -> 'GROUP' objectname description : 
                      make_mc_compliance_group('$2', '$3').

mc_object -> 'OBJECT' objectname syntaxpart writesyntaxpart mc_accesspart description : 
             make_mc_object('$2', '$3', '$4', '$5', '$6').

syntaxpart -> 'SYNTAX' syntax : '$2'.
syntaxpart -> '$empty'        : undefined.

writesyntaxpart -> 'WRITE-SYNTAX' syntax : '$2'.
writesyntaxpart -> '$empty'              : undefined.
    
mc_accesspart -> 'MIN-ACCESS' accessv2 : '$2'.
mc_accesspart -> '$empty'              : undefined.
    
objecttypev2 ->	objectname 'OBJECT-TYPE' 
		'SYNTAX' syntax
                unitspart
               	'MAX-ACCESS' accessv2
		'STATUS' statusv2
                'DESCRIPTION' descriptionfield
                referpart indexpartv2 defvalpart
		nameassign : 
                Kind = kind('$14', '$13'), 
                OT = make_object_type('$1', '$4', '$5', '$7', '$9',
                                      '$11', '$12', Kind, '$15'),
                {OT, line_of('$2')}.

indexpartv2 -> 'INDEX' '{' indextypesv2 '}' : {indexes, lreverse(indexpartv2, '$3')}.
indexpartv2 -> 'AUGMENTS' '{' entry  '}' : {augments, '$3'}.
indexpartv2 -> '$empty' : {indexes, undefined}.

indextypesv2 -> indextypev2 : ['$1'].
indextypesv2 -> indextypesv2 ',' indextypev2 : ['$3' | '$1'].

indextypev2 ->  'IMPLIED' index : {implied,'$2'}.
indextypev2 ->  index : '$1'.

entry -> objectname : '$1'.

unitspart -> '$empty' : undefined.
unitspart -> 'UNITS' string : units('$2') .

statusv2 -> atom : statusv2('$1').
statusv2 -> 'current' : current.
statusv2 -> 'deprecated' : deprecated.
statusv2 -> 'obsolete' : obsolete.

accessv2 -> atom: accessv2('$1').
accessv2 -> 'not-accessible' : 'not-accessible'.
accessv2 -> 'accessible-for-notify' : 'accessible-for-notify'.
accessv2 -> 'read-only' : 'read-only'.
accessv2 -> 'read-write' : 'read-write'.
accessv2 -> 'read-create' : 'read-create'.

notification -> objectname 'NOTIFICATION-TYPE' objectspart
                'STATUS' statusv2 'DESCRIPTION' descriptionfield referpart 
                nameassign :
                Not = make_notification('$1','$3','$5', '$7', '$8', '$9'),
                {Not, line_of('$2')}.

objectspart -> 'OBJECTS' '{' objects '}' : lreverse(objectspart, '$3').
objectspart -> '$empty' : [].

objects -> objectname : ['$1'].
objects -> objects ',' objectname : ['$3'|'$1'].

% Macro definitions - consume and ignore everything between MACRO ::= BEGIN and END
% This is much simpler and handles any macro content without needing to parse it
macrodefinition -> 'MODULE-IDENTITY' 'MACRO' '::=' 'BEGIN' anytokens 'END' : 
                   {ignore_macro, line_of('$2')}.
macrodefinition -> 'TEXTUAL-CONVENTION' 'MACRO' '::=' 'BEGIN' anytokens 'END' : 
                   {ignore_macro, line_of('$2')}.
macrodefinition -> 'OBJECT-TYPE' 'MACRO' '::=' 'BEGIN' anytokens 'END' : 
                   {ignore_macro, line_of('$2')}.
macrodefinition -> 'OBJECT-IDENTITY' 'MACRO' '::=' 'BEGIN' anytokens 'END' : 
                   {ignore_macro, line_of('$2')}.
macrodefinition -> 'TRAP-TYPE' 'MACRO' '::=' 'BEGIN' anytokens 'END' : 
                   {ignore_macro, line_of('$2')}.
macrodefinition -> 'OBJECT-GROUP' 'MACRO' '::=' 'BEGIN' anytokens 'END' : 
                   {ignore_macro, line_of('$2')}.
macrodefinition -> 'NOTIFICATION-GROUP' 'MACRO' '::=' 'BEGIN' anytokens 'END' : 
                   {ignore_macro, line_of('$2')}.
macrodefinition -> 'MODULE-COMPLIANCE' 'MACRO' '::=' 'BEGIN' anytokens 'END' : 
                   {ignore_macro, line_of('$2')}.
macrodefinition -> 'AGENT-CAPABILITIES' 'MACRO' '::=' 'BEGIN' anytokens 'END' : 
                   {ignore_macro, line_of('$2')}.
macrodefinition -> 'NOTIFICATION-TYPE' 'MACRO' '::=' 'BEGIN' anytokens 'END' : 
                   {ignore_macro, line_of('$2')}.
% Handle standalone NOTIFICATION-TYPE macro definitions (like in SNMPv2-SMI)
macrodefinition -> 'NOTIFICATION-TYPE' 'MACRO' '::=' anytokens :
                   {ignore_macro, line_of('$2')}.
% Handle ASN.1 type definitions as ignored constructs for manager context
macrodefinition -> 'Counter' '::=' anytokens :
                   {ignore_typedef, line_of('$2')}.
macrodefinition -> 'Gauge' '::=' anytokens :
                   {ignore_typedef, line_of('$2')}.
macrodefinition -> 'TimeTicks' '::=' anytokens :
                   {ignore_typedef, line_of('$2')}.
macrodefinition -> 'NetworkAddress' '::=' anytokens :
                   {ignore_typedef, line_of('$2')}.
macrodefinition -> 'IpAddress' '::=' anytokens :
                   {ignore_typedef, line_of('$2')}.
macrodefinition -> 'Opaque' '::=' anytokens :
                   {ignore_typedef, line_of('$2')}.

% Very permissive token sequence - matches any tokens until END
anytokens -> '$empty' : [].
anytokens -> anytoken anytokens : ['$1' | '$2'].

% Accept any token as anytoken - this catches everything
anytoken -> atom : '$1'.
anytoken -> string : '$1'.
anytoken -> integer : '$1'.
anytoken -> variable : '$1'.
anytoken -> quote : '$1'.
anytoken -> '{' : '$1'.
anytoken -> '}' : '$1'.
anytoken -> '[' : '$1'.
anytoken -> ']' : '$1'.
anytoken -> '::=' : '$1'.
anytoken -> ':' : '$1'.
anytoken -> '=' : '$1'.
anytoken -> ',' : '$1'.
anytoken -> '.' : '$1'.
anytoken -> '(' : '$1'.
anytoken -> ')' : '$1'.
anytoken -> ';' : '$1'.
anytoken -> '|' : '$1'.
anytoken -> '..' : '$1'.
% Include all terminals as possible tokens inside macros
anytoken -> 'ACCESS' : '$1'.
anytoken -> 'BIT' : '$1'.
anytoken -> 'Counter' : '$1'.
anytoken -> 'DEFINITIONS' : '$1'.
anytoken -> 'DEFVAL' : '$1'.
anytoken -> 'DESCRIPTION' : '$1'.
anytoken -> 'DISPLAY-HINT' : '$1'.
anytoken -> 'ENTERPRISE' : '$1'.
anytoken -> 'EXPORTS' : '$1'.
anytoken -> 'FROM' : '$1'.
anytoken -> 'Gauge' : '$1'.
anytoken -> 'IDENTIFIER' : '$1'.
anytoken -> 'IMPORTS' : '$1'.
anytoken -> 'INDEX' : '$1'.
anytoken -> 'INTEGER' : '$1'.
anytoken -> 'IpAddress' : '$1'.
anytoken -> 'NetworkAddress' : '$1'.
anytoken -> 'OBJECT' : '$1'.
anytoken -> 'OBJECT-TYPE' : '$1'.
anytoken -> 'OCTET' : '$1'.
anytoken -> 'OF' : '$1'.
anytoken -> 'Opaque' : '$1'.
anytoken -> 'REFERENCE' : '$1'.
anytoken -> 'SEQUENCE' : '$1'.
anytoken -> 'SIZE' : '$1'.
anytoken -> 'STATUS' : '$1'.
anytoken -> 'STRING' : '$1'.
anytoken -> 'SYNTAX' : '$1'.
anytoken -> 'TRAP-TYPE' : '$1'.
anytoken -> 'TimeTicks' : '$1'.
anytoken -> 'VARIABLES' : '$1'.
anytoken -> 'current' : '$1'.
anytoken -> 'deprecated' : '$1'.
anytoken -> 'obsolete' : '$1'.
anytoken -> 'mandatory' : '$1'.
anytoken -> 'optional' : '$1'.
anytoken -> 'read-only' : '$1'.
anytoken -> 'read-write' : '$1'.
anytoken -> 'write-only' : '$1'.
anytoken -> 'not-accessible' : '$1'.
anytoken -> 'accessible-for-notify' : '$1'.
anytoken -> 'read-create' : '$1'.
anytoken -> 'TYPE' : '$1'.
anytoken -> 'NOTATION' : '$1'.
anytoken -> 'VALUE' : '$1'.
anytoken -> 'CHOICE' : '$1'.
anytoken -> 'APPLICATION' : '$1'.
anytoken -> 'IMPLICIT' : '$1'.
anytoken -> 'NOTIFICATION-TYPE' : '$1'.
anytoken -> 'NULL' : '$1'.

% Choice elements for ASN.1 CHOICE types
choiceelements -> choiceelement : ['$1'].
choiceelements -> choiceelements ',' choiceelement : ['$3' | '$1'].

choiceelement -> atom syntax : {val('$1'), '$2'}.
choiceelement -> atom : {val('$1'), undefined}.

%%----------------------------------------------------------------------
Erlang code.

%%----------------------------------------------------------------------

% value
val(Token) -> element(3, Token).

line_of(Token) -> element(2, Token).

%% category
cat(Token) -> element(1, Token). 

statusv1(Tok) ->
    case val(Tok) of
        mandatory -> mandatory;
        optional -> optional;
        obsolete -> obsolete;
        deprecated -> deprecated;
        Else -> {error, {list_to_binary("(statusv1) syntax error before: " ++ atom_to_list(Else)), line_of(Tok)}}
    end.

statusv2(Tok) ->
    case val(Tok) of
        current -> current;
        deprecated -> deprecated;
        obsolete -> obsolete;
        Else -> {error, {list_to_binary("(statusv2) syntax error before: " ++ atom_to_list(Else)), line_of(Tok)}}
    end.

ac_status(Tok) ->
    case val(Tok) of
        current -> current;
        obsolete -> obsolete;
        Else -> {error, {list_to_binary("(ac_status) syntax error before: " ++ atom_to_list(Else)), line_of(Tok)}}
    end.

accessv1(Tok) ->
    case val(Tok) of
        'read-only' -> 'read-only';
        'read-write' -> 'read-write';
        'write-only' -> 'write-only';
        'not-accessible' -> 'not-accessible';
        Else -> {error, {list_to_binary("(accessv1) syntax error before: " ++ atom_to_list(Else)), line_of(Tok)}}
    end.

accessv2(Tok) ->
    case val(Tok) of
        'not-accessible' -> 'not-accessible';
        'accessible-for-notify' -> 'accessible-for-notify';
        'read-only' -> 'read-only';
        'read-write' -> 'read-write';
        'read-create' -> 'read-create';
        Else -> {error, {list_to_binary("(accessv2) syntax error before: " ++ atom_to_list(Else)), line_of(Tok)}}
    end.

ac_access(Tok) ->
    case val(Tok) of
        'not-implemented' -> 'not-implemented';
        'accessible-for-notify' -> 'accessible-for-notify';
        'read-only' -> 'read-only';
        'read-write' -> 'read-write';
        'read-create' -> 'read-create';
        'write-only' -> 'write-only';
        Else -> {error, {list_to_binary("(ac_access) syntax error before: " ++ atom_to_list(Else)), line_of(Tok)}}
    end.

%% ---------------------------------------------------------------------
%% Various basic record build functions
%% ---------------------------------------------------------------------

make_module_identity(Name, LU, Org, CI, Desc, Revs, NA) ->
    {mc_module_identity, Name, LU, Org, CI, Desc, Revs, NA}.

make_revision(Rev, Desc) ->
    {mc_revision, Rev, Desc}.

make_object_type(Name, Syntax, MaxAcc, Status, Desc, Ref, Kind, NA) ->
    {mc_object_type, Name, Syntax, undefined, MaxAcc, Status, Desc, Ref, Kind, NA}.

make_object_type(Name, Syntax, Units, MaxAcc, Status, Desc, Ref, Kind, NA) ->
    {mc_object_type, Name, Syntax, Units, MaxAcc, Status, Desc, Ref, Kind, NA}.

make_new_type(Name, Macro, Syntax) ->
    {mc_new_type, Name, Macro, undefined, undefined, undefined, undefined, Syntax}.

make_new_type(Name, Macro, DisplayHint, Status, Desc, Ref, Syntax) ->
    {mc_new_type, Name, Macro, Status, Desc, Ref, DisplayHint, Syntax}.

make_trap(Name, Ent, Vars, Desc, Ref, Num) ->
    {mc_trap, Name, Ent, Vars, Desc, Ref, Num}.

make_notification(Name, Vars, Status, Desc, Ref, NA) ->
    {mc_notification, Name, Vars, Status, Desc, Ref, NA}.

make_agent_capabilities(Name, ProdRel, Status, Desc, Ref, Mods, NA) ->
    {mc_agent_capabilities, Name, ProdRel, Status, Desc, Ref, Mods, NA}.

make_ac_variation(Name, undefined, undefined, Access, undefined, undefined, Desc) ->
    {mc_ac_notification_variation, Name, Access, Desc};
make_ac_variation(Name, Syntax, WriteSyntax, Access, Creation, DefVal, Desc) ->
    {mc_ac_object_variation, Name, Syntax, WriteSyntax, Access, Creation, DefVal, Desc}.

make_ac_module(Name, Grps, Var) ->
    {mc_ac_module, Name, Grps, Var}.

make_module_compliance(Name, Status, Desc, Ref, Mods, NA) ->
    {mc_module_compliance, Name, Status, Desc, Ref, Mods, NA}.

make_mc_module(Name, Mand, Compl) ->
    {mc_mc_module, Name, Mand, Compl}.

make_mc_compliance_group(Name, Desc) ->
    {mc_mc_compliance_group, Name, Desc}.

make_mc_object(Name, Syntax, WriteSyntax, Access, Desc) ->
    {mc_mc_object, Name, Syntax, WriteSyntax, Access, Desc}.

make_object_group(Name, Objs, Status, Desc, Ref, NA) ->
    {mc_object_group, Name, Objs, Status, Desc, Ref, NA}.

make_notification_group(Name, Objs, Status, Desc, Ref, NA) ->
    {mc_notification_group, Name, Objs, Status, Desc, Ref, NA}.

make_sequence(Name, Fields) ->
    {mc_sequence, Name, Fields}.

make_internal(Name, Macro, Parent, SubIdx) ->
    {mc_internal, Name, Macro, Parent, SubIdx}.

make_range_integer(RevHexStr, h) ->
    list_to_integer(lists:reverse(RevHexStr), 16);
make_range_integer(RevHexStr, 'H') ->
    list_to_integer(lists:reverse(RevHexStr), 16);
make_range_integer(RevBitStr, b) ->
    list_to_integer(lists:reverse(RevBitStr), 2);
make_range_integer(RevBitStr, 'B') ->
    list_to_integer(lists:reverse(RevBitStr), 2);
make_range_integer(RevStr, Base) ->
    {error, {invalid_base, Base, list_to_binary(lists:reverse(RevStr))}}.

make_range(XIntList) ->
    IntList = lists:flatten(XIntList),
    {range, lists:min(IntList), lists:max(IntList)}.

make_defval_for_string(_Line, Str, Atom) ->
    case lists:member(Atom, [h, 'H', b, 'B']) of
	true ->
	    case catch make_defval_for_string2(Str, Atom) of
		Defval when is_list(Defval) ->
		    Defval;
		_Error ->
		    ""
	    end;
	false ->
	    ""
    end.

make_defval_for_string2([], h) -> [];
make_defval_for_string2([X16,X|HexString], h) ->
    lists:append(hex_to_bytes([X16,X]), make_defval_for_string2(HexString, h));
make_defval_for_string2([_Odd], h) ->
    throw({error, list_to_binary("odd number of bytes in hex string")});
make_defval_for_string2(HexString, 'H') ->
    make_defval_for_string2(HexString,h);
make_defval_for_string2(BitString, 'B') ->
    bits_to_bytes(BitString);
make_defval_for_string2(BitString, b) ->
    make_defval_for_string2(BitString, 'B').

bits_to_bytes(BitStr) ->
    lists:reverse(bits_to_bytes(lists:reverse(BitStr), 1, 0)).

bits_to_bytes([], 1, _Byte) ->
    [];
bits_to_bytes([], 256, _Byte) ->
    [];
bits_to_bytes([], _N, _Byte) ->
    throw({error, list_to_binary("not a multiple of eight bits in bitstring")});
bits_to_bytes(Rest, 256, Byte) ->
    [Byte | bits_to_bytes(Rest, 1, 0)];
bits_to_bytes([$1 | T], N, Byte) ->
    bits_to_bytes(T, N*2, N + Byte);
bits_to_bytes([$0 | T], N, Byte) ->
    bits_to_bytes(T, N*2, Byte);
bits_to_bytes([_BadChar | _T], _N, _Byte) ->
    throw({error, list_to_binary("bad character in bit string")}).

hex_to_bytes(HexNumber) ->
    case length(HexNumber) rem 2 of
	1 ->
	    hex_to_bytes(lists:append(HexNumber,[$0]),[]);
	0 ->
	    hex_to_bytes(HexNumber,[])
    end.

hex_to_bytes([],R) ->
    lists:reverse(R);
hex_to_bytes([Hi,Lo|Rest],Res) ->
    hex_to_bytes(Rest,[hex_to_byte(Hi,Lo)|Res]).

hex_to_four_bits(Hex) ->
    if
	Hex == $0 -> 0;
	Hex == $1 -> 1;
	Hex == $2 -> 2;
	Hex == $3 -> 3;
	Hex == $4 -> 4;
	Hex == $5 -> 5;
	Hex == $6 -> 6;
	Hex == $7 -> 7;
	Hex == $8 -> 8;
	Hex == $9 -> 9;
	Hex == $A -> 10;
	Hex == $B -> 11;
	Hex == $C -> 12;
	Hex == $D -> 13;
	Hex == $E -> 14;
	Hex == $F -> 15;
	true -> throw({error, list_to_binary("bad hex character")})
    end.

hex_to_byte(Hi,Lo) ->
    (hex_to_four_bits(Hi) bsl 4) bor hex_to_four_bits(Lo).

kind(DefValPart,IndexPart) ->
    case DefValPart of
	undefined ->
	    case IndexPart of
		{indexes, undefined} -> {variable, []};
		{indexes, Indexes}  ->
		    {table_entry, {indexes, Indexes}};
		{augments,Table} ->
		    {table_entry,{augments,Table}}
	    end;
	{defval, DefVal} -> {variable, [{defval, DefVal}]}
    end.    

display_hint(Val) ->
    case val(Val) of
        Str when is_binary(Str) ->
            Str;
        Str when is_list(Str) ->
            list_to_binary(Str);
        _ ->
            throw({error, {invalid_display_hint, Val}})
    end.

units(Val) ->
    case val(Val) of
        Str when is_binary(Str) ->
            Str;
        Str when is_list(Str) ->
            list_to_binary(Str);
        _ ->
            throw({error, {invalid_units, Val}})
    end.

lreverse(_Tag, L) when is_list(L) ->
    lists:reverse(L);
lreverse(Tag, X) ->
    exit({bad_list, Tag, X}).