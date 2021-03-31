// Written in the D programming language.

/**
   This is a submodule of $(MREF std, format).
   It provides some helpful tools.

   Copyright: Copyright The D Language Foundation 2000-2013.

   License: $(HTTP boost.org/LICENSE_1_0.txt, Boost License 1.0).

   Authors: $(HTTP walterbright.com, Walter Bright), $(HTTP erdani.com,
   Andrei Alexandrescu), and Kenji Hara

   Source: $(PHOBOSSRC std/format/read.d)
 */
module std.format.read;

import std.format.spec : FormatSpec;
import std.format.internal.read;
import std.traits : isSomeString;

/**
Reads an input range according to a format string and stores the read
values into its arguments.

The second version of `formattedRead` takes the format string as
template argument. In this case, it is checked for consistency at
compile-time.

Params:
    r = an $(REF_ALTTEXT input range, isInputRange, std, range, primitives),
        where the formatted input is read from
    fmt = a $(MREF_ALTTEXT format string, std,format)
    args = a variadic list of arguments where the read values are stored
    Range = the type of the input range `r`
    Char = the character type used for `fmt`
    Args = a variadic list of types of the arguments

Returns:
    The number of variables filled. If the input range `r` ends early,
    this number will be less than the number of variables provided.

Throws:
    A $(REF_ALTTEXT FormatException, FormatException, std, format)
    if reading did not succeed.

Note:
    For backward compatibility the arguments `args` can be given as pointers
    to that variable, but it is not recommended to do so, because this
    option might be removed in the future.
 */
uint formattedRead(Range, Char, Args...)(auto ref Range r, const(Char)[] fmt, auto ref Args args)
{
    import std.format : enforceFmt;
    import std.range.primitives : empty;
    import std.traits : isPointer;
    import std.typecons : isTuple;

    auto spec = FormatSpec!Char(fmt);
    static if (!Args.length)
    {
        spec.readUpToNextSpec(r);
        enforceFmt(spec.trailing.empty, "Trailing characters in formattedRead format string");
        return 0;
    }
    else
    {
        enum hasPointer = isPointer!(typeof(args[0]));

        // The function below accounts for '*' == fields meant to be
        // read and skipped
        void skipUnstoredFields()
        {
            for (;;)
            {
                spec.readUpToNextSpec(r);
                if (spec.width != spec.DYNAMIC) break;
                // must skip this field
                skipData(r, spec);
            }
        }

        skipUnstoredFields();
        if (r.empty)
        {
            // Input is empty, nothing to read
            return 0;
        }

        static if (hasPointer)
            alias A = typeof(*args[0]);
        else
            alias A = typeof(args[0]);

        static if (isTuple!A)
        {
            foreach (i, T; A.Types)
            {
                static if (hasPointer)
                    (*args[0])[i] = unformatValue!(T)(r, spec);
                else
                    args[0][i] = unformatValue!(T)(r, spec);
                skipUnstoredFields();
            }
        }
        else
        {
            static if (hasPointer)
                *args[0] = unformatValue!(A)(r, spec);
            else
                args[0] = unformatValue!(A)(r, spec);
        }
        return 1 + formattedRead(r, spec.trailing, args[1 .. $]);
    }
}

/// ditto
uint formattedRead(alias fmt, Range, Args...)(auto ref Range r, auto ref Args args)
if (isSomeString!(typeof(fmt)))
{
    import std.format : checkFormatException;

    alias e = checkFormatException!(fmt, Args);
    static assert(!e, e.msg);
    return .formattedRead(r, fmt, args);
}

///
@safe pure unittest
{
    string object;
    char cmp;
    int value;

    assert(formattedRead("angle < 36", "%s %c %d", object, cmp, value) == 3);
    assert(object == "angle");
    assert(cmp == '<');
    assert(value == 36);

    // reading may end early:
    assert(formattedRead("length >", "%s %c %d", object, cmp, value) == 2);
    assert(object == "length");
    assert(cmp == '>');
    // value is not changed:
    assert(value == 36);
}

/// The format string can be checked at compile-time:
@safe pure unittest
{
    string a;
    int b;
    double c;

    assert("hello!124:34.5".formattedRead!"%s!%s:%s"(a, b, c) == 3);
    assert(a == "hello");
    assert(b == 124);
    assert(c == 34.5);
}

@safe unittest
{
    import std.math : isClose, isNaN;
    import std.range.primitives : empty;

    string s = " 1.2 3.4 ";
    double x, y, z;
    assert(formattedRead(s, " %s %s %s ", x, y, z) == 2);
    assert(s.empty);
    assert(isClose(x, 1.2));
    assert(isClose(y, 3.4));
    assert(isNaN(z));
}

// for backwards compatibility
@system pure unittest
{
    string s = "hello!124:34.5";
    string a;
    int b;
    double c;
    formattedRead(s, "%s!%s:%s", &a, &b, &c);
    assert(a == "hello" && b == 124 && c == 34.5);

    // mix pointers and auto-ref
    s = "world!200:42.25";
    formattedRead(s, "%s!%s:%s", a, &b, &c);
    assert(a == "world" && b == 200 && c == 42.25);

    s = "world1!201:42.5";
    formattedRead(s, "%s!%s:%s", &a, &b, c);
    assert(a == "world1" && b == 201 && c == 42.5);

    s = "world2!202:42.75";
    formattedRead(s, "%s!%s:%s", a, b, &c);
    assert(a == "world2" && b == 202 && c == 42.75);
}

// for backwards compatibility
@system pure unittest
{
    import std.math : isClose, isNaN;
    import std.range.primitives : empty;

    string s = " 1.2 3.4 ";
    double x, y, z;
    assert(formattedRead(s, " %s %s %s ", &x, &y, &z) == 2);
    assert(s.empty);
    assert(isClose(x, 1.2));
    assert(isClose(y, 3.4));
    assert(isNaN(z));
}

@system pure unittest
{
    string line;

    bool f1;

    line = "true";
    formattedRead(line, "%s", &f1);
    assert(f1);

    line = "TrUE";
    formattedRead(line, "%s", &f1);
    assert(f1);

    line = "false";
    formattedRead(line, "%s", &f1);
    assert(!f1);

    line = "fALsE";
    formattedRead(line, "%s", &f1);
    assert(!f1);

    line = "1";
    formattedRead(line, "%d", &f1);
    assert(f1);

    line = "-1";
    formattedRead(line, "%d", &f1);
    assert(f1);

    line = "0";
    formattedRead(line, "%d", &f1);
    assert(!f1);

    line = "-0";
    formattedRead(line, "%d", &f1);
    assert(!f1);
}

@system pure unittest
{
    union B
    {
        char[int.sizeof] untyped;
        int typed;
    }

    B b;
    b.typed = 5;
    char[] input = b.untyped[];
    int witness;
    formattedRead(input, "%r", &witness);
    assert(witness == b.typed);
}

@system pure unittest
{
    union A
    {
        char[float.sizeof] untyped;
        float typed;
    }

    A a;
    a.typed = 5.5;
    char[] input = a.untyped[];
    float witness;
    formattedRead(input, "%r", &witness);
    assert(witness == a.typed);
}

@system pure unittest
{
    import std.typecons : Tuple;

    char[] line = "1 2".dup;
    int a, b;
    formattedRead(line, "%s %s", &a, &b);
    assert(a == 1 && b == 2);

    line = "10 2 3".dup;
    formattedRead(line, "%d ", &a);
    assert(a == 10);
    assert(line == "2 3");

    Tuple!(int, float) t;
    line = "1 2.125".dup;
    formattedRead(line, "%d %g", &t);
    assert(t[0] == 1 && t[1] == 2.125);

    line = "1 7643 2.125".dup;
    formattedRead(line, "%s %*u %s", &t);
    assert(t[0] == 1 && t[1] == 2.125);
}

@system pure unittest
{
    string line;

    char c1, c2;

    line = "abc";
    formattedRead(line, "%s%c", &c1, &c2);
    assert(c1 == 'a' && c2 == 'b');
    assert(line == "c");
}

@system pure unittest
{
    string line;

    line = "[1,2,3]";
    int[] s1;
    formattedRead(line, "%s", &s1);
    assert(s1 == [1,2,3]);
}

@system pure unittest
{
    string line;

    line = "[1,2,3]";
    int[] s1;
    formattedRead(line, "[%(%s,%)]", &s1);
    assert(s1 == [1,2,3]);

    line = `["hello", "world"]`;
    string[] s2;
    formattedRead(line, "[%(%s, %)]", &s2);
    assert(s2 == ["hello", "world"]);

    line = "123 456";
    int[] s3;
    formattedRead(line, "%(%s %)", &s3);
    assert(s3 == [123, 456]);

    line = "h,e,l,l,o; w,o,r,l,d";
    string[] s4;
    formattedRead(line, "%(%(%c,%); %)", &s4);
    assert(s4 == ["hello", "world"]);
}

@system pure unittest
{
    import std.exception : assertThrown;

    string line;

    int[4] sa1;
    line = `[1,2,3,4]`;
    formattedRead(line, "%s", &sa1);
    assert(sa1 == [1,2,3,4]);

    int[4] sa2;
    line = `[1,2,3]`;
    assertThrown(formattedRead(line, "%s", &sa2));

    int[4] sa3;
    line = `[1,2,3,4,5]`;
    assertThrown(formattedRead(line, "%s", &sa3));
}

@system pure unittest
{
    import std.exception : assertThrown;
    import std.format : FormatException;

    string input;

    int[4] sa1;
    input = `[1,2,3,4]`;
    formattedRead(input, "[%(%s,%)]", &sa1);
    assert(sa1 == [1,2,3,4]);

    int[4] sa2;
    input = `[1,2,3]`;
    assertThrown!FormatException(formattedRead(input, "[%(%s,%)]", &sa2));
}

@system pure unittest
{
    string line;

    string s1, s2;

    line = "hello, world";
    formattedRead(line, "%s", &s1);
    assert(s1 == "hello, world", s1);

    line = "hello, world;yah";
    formattedRead(line, "%s;%s", &s1, &s2);
    assert(s1 == "hello, world", s1);
    assert(s2 == "yah", s2);

    line = `['h','e','l','l','o']`;
    string s3;
    formattedRead(line, "[%(%s,%)]", &s3);
    assert(s3 == "hello");

    line = `"hello"`;
    string s4;
    formattedRead(line, "\"%(%c%)\"", &s4);
    assert(s4 == "hello");
}

@system pure unittest
{
    string line;

    string[int] aa1;
    line = `[1:"hello", 2:"world"]`;
    formattedRead(line, "%s", &aa1);
    assert(aa1 == [1:"hello", 2:"world"]);

    int[string] aa2;
    line = `{"hello"=1; "world"=2}`;
    formattedRead(line, "{%(%s=%s; %)}", &aa2);
    assert(aa2 == ["hello":1, "world":2]);

    int[string] aa3;
    line = `{[hello=1]; [world=2]}`;
    formattedRead(line, "{%([%(%c%)=%s]%|; %)}", &aa3);
    assert(aa3 == ["hello":1, "world":2]);
}

// test rvalue using
@system pure unittest
{
    string[int] aa1;
    formattedRead!("%s")(`[1:"hello", 2:"world"]`, aa1);
    assert(aa1 == [1:"hello", 2:"world"]);

    int[string] aa2;
    formattedRead(`{"hello"=1; "world"=2}`, "{%(%s=%s; %)}", aa2);
    assert(aa2 == ["hello":1, "world":2]);
}

/**
 * Reads a value from the given _input range according to spec
 * and returns it as type `T`.
 *
 * Params:
 *     T = the type to return
 *     input = the _input range to read from
 *     spec = the `FormatSpec` to use when reading from `input`
 * Returns:
 *     A value from `input` of type `T`
 * Throws:
 *     A `FormatException` if `spec` cannot read a type `T`
 * See_Also:
 *     $(REF parse, std, conv) and $(REF to, std, conv)
 */
T unformatValue(T, Range, Char)(ref Range input, scope const ref FormatSpec!Char spec)
{
    return unformatValueImpl!T(input, spec);
}

/// Booleans
@safe pure unittest
{
    import std.format.spec : singleSpec;

    auto str = "false";
    auto spec = singleSpec("%s");
    assert(unformatValue!bool(str, spec) == false);

    str = "1";
    spec = singleSpec("%d");
    assert(unformatValue!bool(str, spec));
}

/// Null values
@safe pure unittest
{
    import std.format.spec : singleSpec;

    auto str = "null";
    auto spec = singleSpec("%s");
    assert(str.unformatValue!(typeof(null))(spec) == null);
}

/// Integrals
@safe pure unittest
{
    import std.format.spec : singleSpec;

    auto str = "123";
    auto spec = singleSpec("%s");
    assert(str.unformatValue!int(spec) == 123);

    str = "ABC";
    spec = singleSpec("%X");
    assert(str.unformatValue!int(spec) == 2748);

    str = "11610";
    spec = singleSpec("%o");
    assert(str.unformatValue!int(spec) == 5000);
}

/// Floating point numbers
@safe pure unittest
{
    import std.format.spec : singleSpec;
    import std.math : isClose;

    auto str = "123.456";
    auto spec = singleSpec("%s");
    assert(str.unformatValue!double(spec).isClose(123.456));
}

/// Character input ranges
@safe pure unittest
{
    import std.format.spec : singleSpec;

    auto str = "aaa";
    auto spec = singleSpec("%s");
    assert(str.unformatValue!char(spec) == 'a');

    // Using a numerical format spec reads a Unicode value from a string
    str = "65";
    spec = singleSpec("%d");
    assert(str.unformatValue!char(spec) == 'A');

    str = "41";
    spec = singleSpec("%x");
    assert(str.unformatValue!char(spec) == 'A');

    str = "10003";
    spec = singleSpec("%d");
    assert(str.unformatValue!dchar(spec) == '✓');
}

/// Arrays and static arrays
@safe pure unittest
{
    import std.format.spec : singleSpec;

    string str = "aaa";
    auto spec = singleSpec("%s");
    assert(str.unformatValue!(dchar[])(spec) == "aaa"d);

    str = "aaa";
    spec = singleSpec("%s");
    dchar[3] ret = ['a', 'a', 'a'];
    assert(str.unformatValue!(dchar[3])(spec) == ret);

    str = "[1, 2, 3, 4]";
    spec = singleSpec("%s");
    assert(str.unformatValue!(int[])(spec) == [1, 2, 3, 4]);

    str = "[1, 2, 3, 4]";
    spec = singleSpec("%s");
    int[4] ret2 = [1, 2, 3, 4];
    assert(str.unformatValue!(int[4])(spec) == ret2);
}

/// Associative arrays
@safe pure unittest
{
    import std.format.spec : singleSpec;

    auto str = `["one": 1, "two": 2]`;
    auto spec = singleSpec("%s");
    assert(str.unformatValue!(int[string])(spec) == ["one": 1, "two": 2]);
}

// https://issues.dlang.org/show_bug.cgi?id=7241
@safe pure unittest
{
    string input = "a";
    auto spec = FormatSpec!char("%s");
    spec.readUpToNextSpec(input);
    auto result = unformatValue!(dchar[1])(input, spec);
    assert(result[0] == 'a');
}
