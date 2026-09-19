{smcl}
{* *! version april 2015}{...}
{hi:help sreshape}{right: ({browse "http://www.stata-journal.com/article.html?article=dm0090":SJ16-3: dm0090})}
{hline}

{title:Title}

{p2colset 5 17 19 2}{...}
{p2col :{hi:sreshape} {hline 2}}Reshape data, speedily and sparsely{p_end}
{p2colreset}{...}


{title:Syntax}

{p 8 16 2}
{cmd:sreshape} {cmd:long} {it:stubnames}{cmd:,} [{opth i(varlist)}
{opth newi(newvar)} {cmd:j(}{it:{help varname}} [{it:values}]{cmd:)}
{opt s:tring}
{cmdab:mi:ssing(keep}|{cmd:drop}|{cmd:drop all)} {opt norec:astasdouble}
{cmdab:f:avorspace(0}|{cmd:1}|{cmd:2}|{cmd:3}|{cmd:4)} {opt nopreserve}]

{p 8 16 2}
{cmd:sreshape} {cmd:wide} {it:stubnames}{cmd:,} [{opth i(varlist)}
{cmd:j(}{it:{help varname}} [{it:values}]{cmd:)} {opt s:tring}
{cmdab:w:idevars(all}|{cmd:nonmissing)}
{opt nocom:press} {opt atwl(string)}
{cmdab:f:avorspace(0}|{cmd:1}|{cmd:2}|{cmd:3}|{cmd:4)}
{opt nopreserve}]

{synoptset 29 tabbed}{...}
{synopthdr}
{synoptline}
{syntab:Main}
{p2coldent:* {opth i(varlist)}}specify i variables{p_end}
{synopt:{opth newi(newvar)}}alternative to {opt i(varlist)} to generate a new i variable{p_end}
{synopt:{cmd:j(}{it:{help varname}} [{it:values}]{cmd:)}}specify j variable name (default is _j) and values if desired{p_end}
{synopt:{opt s:tring}}allow j values to be strings{p_end}

{syntab:Sparse (partially missing) data}
{synopt:{cmdab:mi:ssing(keep}|{cmd:drop}|{cmd:drop all)}}optionally drop long
observations for which all Xij wide values are missing, keeping at least one
long observation per i value if {cmd:drop} is specified instead of {cmd:drop}
{cmd:all}{p_end}
{synopt:{cmdab:w:idevars(all}|{cmd:nonmissing)}}optionally do not create Xij wide variables whose values would always be missing{p_end}

{syntab:Advanced}
{synopt:{opt nocom:press}}do not compress Xij wide variable types (default is to compress when possible){p_end}
{synopt:{opt norec:astasdouble}}if very large long numbers are being combined with one or more float variables, prevent conversion to double to save space at some cost in precision{p_end}
{synopt:{opt atwl(string)}}in long form variable names, substitute {cmd:@} signs
with this string (use "{cmd:.}" for null; otherwise, prior advanced setting is used){p_end}
{synopt:{cmdab:f:avorspace(0}|{cmd:1}|{cmd:2}|{cmd:3}|{cmd:4)}}favor greater
savings of memory over speed, in select circumstances (default of {cmd:0} favors speed over space){p_end}
{synopt:{opt nopreserve}}(programmer's option) prevent preserving data because the calling program has already preserved{p_end}
{synoptline}
{p2colreset}{...}
{p 4 6 2}* {opt i(varlist)} or {opt newi(newvar)} is required for
{opt sreshape long}, or {opt i(varlist)} is required for
{opt sreshape wide}.{p_end}


{title:Description}

{pstd}
A fundamental data transformation is reshaping between wide and long forms of
data.  Stata's {helpb reshape} command allows this reshaping.  The
{cmd:sreshape} command is just like {cmd:reshape} but is speedier and
sparser.  It is sparser in the sense that it can automatically drop long-form
observations whose Xij data are all missing and wide-form variables whose Xij
data are all missing.

{pstd}
Users can simply use {cmd:sreshape} in place of their usual {cmd:reshape}
commands by typing an "s" in front of the usual command name.  Experiments
suggest that this typically gives a speedup of 8 to 31 times going from wide
to long, or 2 to 13 times going from long to wide, with large datasets.  The
exact speedup depends on the particular data and machine.  In special
circumstances, notably if your data have {cmd:strL} variables with very long
values often exactly repeated, {cmd:reshape} might be faster than
{cmd:sreshape}.  Also, if your data are close to exceeding the computer's
memory, {cmd:reshape} might be faster (because of the possibility of exceeding
available memory and forcing the operating system to rely on virtual memory).
By building on {cmd:reshape}, StataCorp might readily achieve faster speedups
with internal implementation in the future.

{pstd}
The "sparse" aspects of {cmd:sreshape} are for data that are sparse in the
sense that they contain at least some -- often a high proportion of -- missing
data.  For example, suppose you have data about patents in wide form.  The
data list the inventors of each patent and the locations of those inventors.
Some patents have a single inventor, typical patents have a few inventors, but
some patents have hundreds or thousands of inventors.  In wide form, the
variables include {cmd:inventor1}, {cmd:inventor2}, ..., {cmd:inventor}{it:#}
(where {it:#} is in the hundreds or thousands) plus {cmd:invlocation1},
{cmd:invlocation2}, ..., {cmd:invlocation}{it:#}.  In this wide form, most of
the cells of data contain missing values because most patents have fewer than
10 inventors.  In long form, the same data will be represented with one
observation for each patent-inventor pair.  The standard {cmd:reshape} command
in Stata creates {it:#} observations for each inventor, with each observation
listing the inventor and the inventor's location in variables {cmd:inventor}
and {cmd:invlocation}.  Most of these {it:#} observations have empty cells for
the inventor and the location.  Using the {cmd:missing(drop)} option with
{cmd:sreshape wide} suppresses the creation of long-form observations that
would have empty (that is, missing) values for both the {cmd:inventor} and
{cmd:invlocation} variables, except that at least one observation (the
lowest-numbered if all observations are empty) is retained.  The reason to
retain at least one observation is that any other important data associated
with each patent may need to be retained, for example, the patent's
publication number and title (variables {cmd:pubnum} and {cmd:title}), the
number of times the patent has been cited in other patents (variable
{cmd:ncites}), and simply the fact that a patent existed at all (this is
apparent given the unique value of its i variable or variables).  If such
extra information is not needed when there is no inventor information, then
the {cmd:missing(drop all)} option can be used to suppress creation of every
long-form observation that would lack inventor information, without trying to
retain the extra information.

{pstd}
Another "sparse" aspect of some data is that in wide form, certain variables
would contain only missing values.  For example, the locations of the
inventors may be known only for the first five inventors.  In this case, the
usual {cmd:sreshape} creates many variables ({cmd:invlocation6},
{cmd:invlocation7}, ..., {cmd:invlocation}{it:#}) that contain nothing but
missing values.  The {cmd:widevars(nonmissing)} option suppresses creation of
such wide variables that would contain only missing data.

{pstd}
With very sparse data, in the sense of large numbers of missing values, the
{cmd:missing(drop}|{cmd:drop all)} and {cmd:widevars(nonmissing)} options will
further speed up the reshaping process.

{pstd}
Even when the wide data are nonmissing, they may often contain only small
integers that can be stored compactly using data types {cmd:byte}, {cmd:int},
or {cmd:long}, with no loss of information.  The {cmd:sreshape wide} command
automatically uses the most compact data type that stores the data without
loss of information, saving memory for your computer and your datasets.  You
can override this behavior with the {opt nocompress} option.

{pstd}
Going from wide to long data, the wide data often have variables of multiple
types.  In long form, the data are converted to the appropriate type needed to
store the data without any loss of information.  If the wide data include
variables of both float and long types and these variables are
combined into one long variable, {cmd:sreshape} checks the numbers that
were originally of long type to see if they are so large that they might not
be stored with full precision using the float type.  When there could be
a loss of precision, {cmd:sreshape} automatically uses double-precision
variables in long form so that there will be no loss of precision and no loss
of information.  Preventing such loss of information is especially important
if the long-type variables represent identification codes such as patent
numbers.  For example, patent number 16,777,219 is totally different from
patent number 16,777,218, even though the numbers are almost the same.
Avoiding precision loss requires using double precision for integers that
exceed 16,777,216, so double-precision variables are created when the original
data contained one or more such integers and they must be combined with
float-type variables.  If you do not want to keep the original precision and
instead want to just use float-type variables, use the {opt norecastasdouble}
option.

{pstd}
Although some options pertain only to {cmd:sreshape long} or
{cmd:sreshape wide} and not to both, it might be painstaking to carefully
list options only with the right command.  Therefore, any options can be used
with either of the commands -- even when they do not have any effect -- except
that {opt newi(newvar)} may be used only with {cmd:sreshape long}.

{pstd}
When the data are in wide form, there may not be a preexisting "i" variable
that identifies the individual unit to which the row of data pertains.  Using
{opt newi(newvar)} automatically creates such a variable with the name you
specify, with a unique number for each observation.  You could do the same by
typing the {cmd:generate inum = _n} command to generate a variable named
{cmd:inum}, before calling {cmd:sreshape long} with the {cmd:i(inum)} option.
The {opt newi(newvar)} option is merely a convenience.

{pstd}
The stubnames may contain the {cmd:@} symbol, in which case j values replace
the {cmd:@} symbol in wide variable names.  If there is no {cmd:@} symbol, j
values are appended after the stubnames.  In long form, the {opt atwl(string)}
option may be used to replace {cmd:@} with a specified string (consisting of
letters, numbers, or underscore in a manner that yields valid variable names).
If {opt atwl(string)} is not specified, any prior setting used with
{cmd:reshape} or {cmd:sreshape} is used instead -- although this treatment is
awkward, it maintains compatibility with the existing {cmd:reshape} command.
To make the atwl replacement string null, you must use {cmd:atwl(".")}.  Be
careful: specifying {cmd:atwl("")} will fail to make this value null; instead,
you must use {cmd:atwl(".")}.

{pstd}
The {cmd:reshape} command also allows an advanced form, and {cmd:sreshape}
honors the same advanced form usages, with one exception.  The {cmd:reshape}
{cmd:xi} advanced usage is not supported because it could cause unintentional
dropping of variables (however, see the denigrated
{opt keeponlyxi(varlist)} option if this is really needed).  See the online
help and manual for {cmd:reshape} for further information.  Options not
supported in the {cmd:reshape} command must be entered directly with the
{cmd:sreshape} {cmd:long} and {cmd:sreshape} {cmd:wide} commands.

{pstd}
The {cmd:sreshape} command is interoperable with {cmd:reshape}.  After you use
{cmd:reshape}, {cmd:sreshape} will know how to reshape your data, and after
you use {cmd:sreshape}, {cmd:reshape} will know how to reshape your data.
However, any options that are in {cmd:sreshape} and are not included in
{cmd:reshape} must be specified with the command every time.  It is not
sufficient just to type {cmd:sreshape long} or  {cmd:sreshape wide} without
options, if in fact you mean to include these options.


{title:Options}

{dlgtab:Main}

{phang}
{opth i(varlist)}
identifies unique individuals in the sample.  That is, there must be a unique
combination of these "i" variables for each individual.  See {helpb reshape}
for examples.  This option must be specified for long-to-wide transformations,
or either {opt i(varlist)} or {opt newi(newvar)} must be specified for
wide-to-long transformations.

{phang}
{opth newi(newvar)}
generates a new i variable with the specified name and sets it equal to the
observation number in the data.  This option may be used instead of
{opt i(varlist)} but only with {cmd:sreshape long}.

{phang}
{cmd:j(}{it:{help varname}} [{it:values}]{cmd:)}
specifies the name of the variable in long form and identifies the
subcategories of observations within each individual, such as different years
of data for each person in a sample.  Usually, the values of this variable, the
so-called j values, are determined automatically from the data.
Alternatively, a list of all the values of the j variable may be provided
after the variable name.  If the list is provided, then with
{cmd:sreshape long}, this list of values will be used instead of an
automatically determined list.  The list of values takes the same form as in
{cmd:reshape}, that is, either a list of numbers, {it:#}[-{it:#}] [...], or a
list of strings, {it:string} [{it:string} ...], separated with spaces.  With
{cmd:sreshape wide}, only automatically determined values will be used (if you
list a value and it is not in the automatically determined list,
{cmd:sreshape} notes this discrepancy in the program output).

{phang}
{opt string}
indicates that the j values may be strings.  Otherwise, only numeric values are
considered.  Because the j values become parts of variable names when the data
are in wide form, these strings must yield valid variable names.  They may
include letters, numeric digits, the underscore ("_") character, and Unicode
letters.

{dlgtab:Sparse (partially missing) data}

{phang}
{cmd:missing(keep}|{cmd:drop}|{cmd:drop all)}
determines how {cmd:sreshape long} treats the reshaped data.  The default is
{cmd:missing(keep)}, meaning to keep all observations in the reshaped data, as
in Stata's official {cmd:reshape} command.  Specifying {cmd:missing(drop)}
causes observations with nonmissing Xij data (the reshaped variables) to be
kept but other observations to be dropped, except that at least one j value is
kept per individual (that is, per i variable combination) in the sample.
Keeping at least one j value per individual means that Xi data are still
available in the data, and the data still retain the fact that an individual
is in the sample.  Alternatively, {cmd:missing(drop all)} causes all
observations with entirely missing Xij data to be dropped, even if that leaves
zero observations for some individuals.

{phang}
{cmd:widevars(all}|{cmd:nonmissing)}
determines how {cmd:sreshape wide} treats the reshaped data.  The default is
{cmd:widevars(all)}, meaning to keep all variables in wide form, even if they
are filled with missing data in every observation.  The alternative,
{cmd:widevars(nonmissing)}, does not generate wide variables if they would
contain nothing but missing data.

{dlgtab:Advanced}

{phang}
{opt nocompress}
causes {cmd:sreshape wide} to keep the wide Xij variables in the same data type
as in long form.  The default is instead to compress the wide variables when
that is possible without loss of information.  For example, if the values of a
wide-form variable are all integers between -127 and 100, they can be stored
as byte variables to take up less space.

{phang}
{opt norecastasdouble}
is unlikely to be needed.  When {cmd:sreshape long} combines multiple
wide-form variables into a single long-form variable, and the combined
variables include variables of both float and integer types, {cmd:sreshape}
automatically uses a combined variable type of double when necessary to ensure
that the integer variables do not suffer loss of precision.  If you would
rather allow the loss of precision and store the data as type float, use this
option.

{phang}
{opt atwl(string)}
specifies how to treat {cmd:@} signs in stubnames when making long-form Xij
variable names.  In wide form, the {cmd:@} signs are replaced with j values,
instead of the default of putting the j values at the ends of wide variable
names.  In long form, the {cmd:@} sign is usually just deleted, but this
option allows replacement with a string instead.  The string must consist only
of legal characters for variable names (letters, digits, or underscore).  If
this option was specified previously in the advanced form of {cmd:reshape},
the prior advanced setting continues to apply -- to maintain compatibility
with Stata's {cmd:reshape} command -- unless you change it.  To replace a
prior setting with null, you must use {cmd:atwl(".")}.  That is,
{cmd:atwl("")} means no change, so you must use {cmd:atwl(".")}.

{phang}
{cmd:favorspace(0}|{cmd:1}|{cmd:2}|{cmd:3}|{cmd:4)}
allows users to favor space, under certain circumstances, at the expense of
slower operation.  Larger numbers favor space more at a greater cost in speed,
again under certain circumstances.  The default value of {cmd:0} favors speed.
The next value, 1, indicates that {cmd:sreshape} should use a Java plugin when
it would help to save space (for numeric variables that are not doubles), but
this will work only if Java is installed on your computer (Java is already
installed on many computers for web browser use and is a free download).
Higher values take effect if Java is not available and integer-type variables
are used.  These values cause the integers to be stored temporarily in
approximately 1/8 (byte), 1/4 (int), or 1/2 (long) the amount of memory
otherwise required but with a substantial penalty in computational time, with
bytes having a big penalty, ints having a bigger penalty, and longs having the
biggest penalty.  Choosing 2 for this option causes only bytes to be stored in
less memory, choosing 3 causes bytes and ints to be stored in less memory, and
choosing 4 causes bytes, ints, and longs to be stored in less memory.  This
option may be helpful if your computer is running out of available memory.
(This could cause it to slow down enormously as it starts using "virtual
memory", in which case it uses a disk drive as a place to temporarily relocate
contents of its internal RAM memory.  So if your computer seems suddenly very
sluggish, this option may help.)

{phang}
{opt nopreserve}
is a programmer's option for use when writing programs that have already
preserved the data at the time {cmd:sreshape} is called.  This causes
{cmd:sreshape} to leave the data messed up if the user presses the Break key
or if there is an error in operation.  It saves some time but should be
used only by programmers who understand the need to preserve the data before
calling {cmd:sreshape}.

{dlgtab:Denigrated}

{phang}
{opth keeponlyxi(varlist)}
should probably not be used.  It specifies that only the specified Xi
variables (variables constant within i but possibly varying across i, other
than the list in {opt i(varlist)} or {opt newi(newvar)}) be kept;
all other Xi variables are dropped.  Do not use this option unless you truly
think it necessary to maintain compatibility with prior work.  This option is
given only to allow some compatibility with reshape regarding its Xi advanced
option.  Otherwise, prior settings of the list of Xi variables to keep,
including advanced format settings with {cmd:reshape xi}, cause an error
message, warning that instead the user should explicitly drop undesired
variables.


{title:Remarks}

{pstd}
{cmd:sreshape} allows careful treatment of sparse data features common in many
datasets.  Its other advantage is speed.  The speed advantage may be
compromised under certain circumstances, notably when the computer's memory is
close to full (also when there are strL-type variables with very many
long and identical values).  The command lays the groundwork so that StataCorp
could easily implement a better version that is even faster and that does not
suffer from the speed limitations of {cmd:sreshape}.  For further information,
see Simons (2016).


{title:Examples}

{pstd}
The command can work just like {cmd:reshape} by putting an "s" in front of
the command name.  For example,

{phang}{cmd:. webuse reshape1}

{phang}{cmd:. sreshape long inc ue, i(id) j(year)}

{phang}{cmd:. sreshape wide}

{phang}{cmd:. webuse reshape3, clear}

{phang}{cmd:. sreshape long inc@r ue, i(id) j(year)}

{phang}{cmd:. webuse reshape4, clear}

{phang}{cmd:. sreshape long inc, i(id) j(sex) string}

{pstd}
Use the {cmd:missing(drop)} option to drop observations with only missing Xij
data when using {cmd:sreshape long}.

{phang}{cmd:. webuse reshape1}

{phang}{cmd:. replace inc80 = . in 2}

{phang}{cmd:. replace ue80 = . in 2}

{phang}{cmd:. sreshape long inc ue, i(id) j(year) missing(drop)}

{pstd}
Use the {cmd:missing(drop all)} option to drop every observation with only
missing Xij data when using {cmd:sreshape long}, even if that drops some
individuals (and their constant or "Xi" variables) from the data.

{phang}{cmd:. webuse reshape1}

{phang}{cmd:. replace inc80 = . in 2}

{phang}{cmd:. replace inc81 = . in 2}

{phang}{cmd:. replace inc82 = . in 2}

{phang}{cmd:. replace ue80 = . in 2}

{phang}{cmd:. replace ue81 = . in 2}

{phang}{cmd:. replace ue82 = . in 2}

{phang}{cmd:. sreshape long inc ue, i(id) j(year) missing(drop all)}

{pstd}
When using {cmd:sreshape wide}, use the {cmd:widevars(nonmissing)} option to
suppress creation of Xij wide variables that would contain nothing but missing
values.

{phang}{cmd:. sreshape wide inc ue, i(id) j(year) widevars(nonmissing)}


{marker stored_results}{...}
{title:Stored results}

{pstd}
{cmd:sreshape} stores the following in {cmd:r()}:

{synoptset 15 tabbed}{...}
{p2col 5 15 19 2: Scalars}{p_end}
{synopt:{cmd:r(k)}}number of variables after reshaping{p_end}
{synopt:{cmd:r(N)}}number of observations after reshaping{p_end}
{synopt:{cmd:r(changed)}}{cmd:1} if the data have been changed, {cmd:0} if not{p_end}
{synopt:{cmd:r(width)}}number of bytes needed to store each observation's data in the main Stata dataset, after reshaping{p_end}
{p2colreset}{...}


{title:Reference}

{phang}
Simons, K. L. 2016.
{browse "http://www.stata-journal.com/article.html?article=dm0090":A sparser, speedier reshape}
{it:Stata Journal} 16: 632-649.


{title:Author}

{pstd}Kenneth L. Simons{p_end}
{pstd}Department of Economics {p_end}
{pstd}Rensselaer Polytechnic Institute{p_end}
{pstd}{browse "http://www.rpi.edu/~simonk"}{p_end}


{title:Also see}

{p 4 14 2}
Article:  {it:Stata Journal}, volume 16, number 3: {browse "http://www.stata-journal.com/article.html?article=dm0090":dm0090}

{p 5 14 2}
Manual:  {manlink D reshape}

{p 7 14 2}
Help:  {helpb reshape}
{p_end}
