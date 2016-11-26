#include "wstp.h"
#include "iostream"
#include "boost/python.hpp"
#include <string.h>

using namespace std;
using namespace boost::python;

unsigned const char* buffer;
int bytes;
int characters;

void PyGet(object const& py_obj);
object PyPut(int object_type);
void ExceptonHandle(const char* s);

object main_module;
object main_namespace;
object __buildin__str;

int main(int argc, char* argv[])
{
    Py_Initialize();
    main_module = import("__main__");
    main_namespace = main_module.attr("__dict__");
    __buildin__str = eval("str", main_namespace);
    return WSMain(argc, argv);
}

:Begin:
:Function:		PyExec
:Pattern:		PyExec[code:_String]
:Arguments:		{code}
:ArgumentTypes:	{Manual}
:ReturnType:	Null
:End:
:Evaluate: PyExec::Error = "File '`1`', line `2`, `3`"
void PyExec()
{
    try {
        WSGetUTF8String(stdlink, &buffer, &bytes, &characters);
        exec((char*)buffer, main_namespace);
        WSReleaseUTF8String(stdlink, buffer, bytes);
        return;
    }
    catch (error_already_set const&) {
        ExceptonHandle("PyExec");
        WSEvaluateString(stdlink, "$Failed");
        return;
    }
}

:Begin:
:Function:		PyGet
:Pattern:		PyGet[name:_String]
:Arguments:		{name}
:ArgumentTypes:	{Manual}
:ReturnType:	Manual
:End:
:Evaluate: PyGet::Error = "File '`1`', line `2`, `3`"
void PyGet()
{
    try {
        WSGetUTF8String(stdlink, &buffer, &bytes, &characters);
        object obj = eval((char*)buffer, main_namespace);
        WSReleaseUTF8String(stdlink, buffer, bytes);
        PyGet(obj);
        return;
    }
    catch (error_already_set const&) {
        ExceptonHandle("PyGet");
		WSPutSymbol(stdlink, "$Failed");
        return;
    }
}

void PyGet(object const& obj)
{
    string class_name = extract<string>(obj.attr("__class__").attr("__name__"));
    if (class_name == "int") {
        string s = extract<string>(__buildin__str(obj));
        WSPutFunction(stdlink, "ToExpression", 1);
        WSPutString(stdlink, s.c_str());
        return;
    }
    else if (class_name == "float") {
        WSPutReal64(stdlink, extract<double>(obj));
        return;
    }
    else if (class_name == "complex") {
        WSPutFunction(stdlink, "Complex", 2);
        WSPutReal64(stdlink, extract<double>(obj.attr("real")));
        WSPutReal64(stdlink, extract<double>(obj.attr("imag")));
        return;
    }
    else if (class_name == "s") {
        string s = extract<string>(obj);
        const char* str_bytes = s.c_str();
        WSPutUTF8String(stdlink, (unsigned const char*)str_bytes, strlen(str_bytes));
        return;
    }
    else if (class_name == "tuple" || class_name == "list") {
        int len = extract<int>(obj.attr("__len__")());
        WSPutFunction(stdlink, "List", len);
        for (int i = 0; i < len; ++i) {
            object item = obj.attr("__getitem__")(i);
            PyGet(item);
        }
    }
    else if (class_name == "dict") {
        object keys = list(obj.attr("keys")());
        int len = extract<int>(keys.attr("__len__")());
        WSPutFunction(stdlink, "List", len);
        for (int i = 0; i < len; ++i) {
            WSPutFunction(stdlink, "List", 2);
            PyGet(keys[i]); //hehe
            PyGet(obj[keys[i]]); //hehe
        }
        return;
    }
    else {
        string s = extract<string>(__buildin__str(obj));
        const char* str_bytes = s.c_str();
        WSPutUTF8String(stdlink, (unsigned const char*)str_bytes, strlen(str_bytes));
    }
}

:Begin:
:Function:      PyPut
:Pattern:       PyPut[name:_String, value:_]
:Arguments:     {name, value}
:ArgumentTypes: {Manual}
:ReturnType:    Null
:End:
void PyPut(void)
{
    WSGetUTF8String(stdlink, &buffer, &bytes, &characters);
    string name = (char*)buffer;
    WSReleaseUTF8String(stdlink, buffer, bytes);
    int object_type = WSGetType(stdlink);
    cout << object_type << endl;
    try {
        main_namespace.attr("__setitem__")(name, PyPut(object_type));
    }
    catch (error_already_set const&) {
        PyErr_Print();
        WSEvaluateString(stdlink, "$Failed");
        return;
    }
    return;
}

object PyPut(int object_type)
{
    if (object_type == WSTKINT) {
        WSGetUTF8String(stdlink, &buffer, &bytes, &characters);
        string s = (char*)buffer;
        WSReleaseUTF8String(stdlink, buffer, bytes);
        object obj = long_(s);
        return obj;
    }
    else if (object_type == WSTKREAL) {
        double d;
        WSGetReal64(stdlink, &d);
        return object(d);
    }
    else if (object_type == WSTKSTR || object_type == WSTKSYM) {
        WSGetUTF8String(stdlink, &buffer, &bytes, &characters);
        string s = (char*)buffer;
        WSReleaseUTF8String(stdlink, buffer, bytes);
        object obj = str(s);
        return obj;
    }
    else if (object_type == WSTKFUNC) {
        const char* f;
        int n;
        WSGetFunction(stdlink, &f, &n);
        if (strcmp(f, "List") == 0) {
            object obj = eval("[None]", main_namespace).attr("__rmul__")(n);
            for (int i = 0; i < n; ++i) {
                int object_type = WSGetType(stdlink);
                obj[i] = PyPut(object_type);
            }
            return obj;
        }
        else if (strcmp(f, "Complex") == 0) {
            double real;
            double imag;
            WSGetReal64(stdlink, &real);
            WSGetReal64(stdlink, &imag);
            return eval("complex", main_namespace)(real, imag);
        }
        else {
            object obj = eval("[None,None]");
            string s = (char*)f;
            obj[0] = object(s);
            obj[1] = n;
            return obj;
        }
    }
}

inline void ExceptonHandle(const char* mmaFunction)
{
    // print exception infomation to console
    PyErr_Print();

    // print exceptions infomation to mma(exist some bugs to be fixed)

    // PyObject* ptype;
    // PyObject* pvalue;
    // PyObject* ptraceback;
    // PyErr_Fetch(&ptype, &pvalue, &ptraceback);

    // handle<> hType(ptype);
    // object extype(hType);
    // handle<> hTraceback(ptraceback);
    // object traceback(hTraceback);

    // string strErrorMessage = extract<string>(pvalue);
    // int lineNo = extract<int>(traceback.attr("tb_lineno"));
    // string fileName = extract<string>(traceback.attr("tb_frame").attr("f_code").attr("co_filename"));
    // string funcName = extract<string>(traceback.attr("tb_frame").attr("f_code").attr("co_name"));

    // char* buffer = new char[1024];
    // sprintf(buffer, "Message[%s::Error,\"%s\",%d,\"%s\"]",
    //     mmaFunction,
    //     (unsigned const char*)fileName.c_str(),
    //     lineNo,
    //     (unsigned const char*)strErrorMessage.c_str());
    // printf("%s\n", buffer);
    // WSEvaluateString(stdlink, buffer);
    // delete[] buffer;

    return;
}