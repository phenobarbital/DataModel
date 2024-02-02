# cython: language_level=3, embedsignature=True, boundscheck=False, wraparound=True, initializedcheck=False
# Copyright (C) 2018-present Jesus Lara
#
import re
import inspect
import logging # migrate to use cprint
import ciso8601
from typing import get_args, get_origin, Union, Optional
from dataclasses import _MISSING_TYPE, _FIELDS, fields
import orjson
from decimal import Decimal
from cpython cimport datetime
import pendulum
from pendulum.parsing.exceptions import ParserError
from uuid import UUID
from cpython.ref cimport PyObject
from .validation import is_dataclass, is_iterable


cdef object to_uuid(object obj):
    """Returns a UUID version of a str column.
    """
    if isinstance(obj, UUID):
        # already an uuid
        return obj
    elif callable(obj):
        # its a function callable returning a value
        try:
            return obj()
        except:
            pass
    try:
        return UUID(str(obj))
    except ValueError:
        return None

cpdef str slugify_camelcase(str obj):
    """slugify_camelcase.

    Converting a CamelCase String into a version.
    """
    slugified = [obj[0]]
    for c in obj[1:]:
        if c.isupper():
            slugified.append(' ')
        slugified.append(c)
    return ''.join(slugified)

cpdef datetime.date to_date(object obj):
    """to_date.

    Returns obj converted to date.
    """
    if obj is None:
        return None
    if isinstance(obj, datetime.date):
        return obj
    elif isinstance(obj, str):
        try:
            return ciso8601.parse_datetime(obj).date()
        except ValueError:
            pass
    if isinstance(obj, (bytes, bytearray)):
        obj = obj.decode("ascii")
    try:
        return datetime.datetime.fromisoformat(obj).date()
    except ValueError:
        pass
    try:
        return pendulum.parse(obj, strict=False).date()
    except (ValueError, TypeError, ParserError):
        raise ValueError(
            f"Can't convert invalid data *{obj}* to date"
        )

cpdef datetime.datetime to_datetime(object obj):
    """to_datetime.

    Returns obj converted to datetime.
    """
    if obj is None:
        return None
    if isinstance(obj, datetime.datetime):
        return obj
    elif obj == _MISSING_TYPE:
        return None
    elif isinstance(obj, str):
        try:
            return ciso8601.parse_datetime(obj)
        except ValueError:
            pass
    if isinstance(obj, (bytes, bytearray)):
        obj = obj.decode("ascii")
    try:
        return datetime.datetime.fromisoformat(obj)
    except ValueError:
        pass
    try:
        return pendulum.parse(obj, strict=False)
    except (ValueError, TypeError, ParserError):
        raise ValueError(
            f"Can't convert invalid data *{obj}* to datetime"
        )

cpdef object to_integer(object obj):
    """to_integer.

    Returns object converted to integer.
    """
    if obj is None:
        return None
    if isinstance(obj, int):
        return obj
    elif callable(obj):
        # its a function callable returning a value
        try:
            return obj()
        except:
            pass
    else:
        try:
            return int(obj)
        except (TypeError, ValueError) as e:
            raise ValueError(
                f"Invalid conversion to Integer of {obj}"
            ) from e

cpdef object to_float(object obj):
    """to_float.

    Returns object converted to float.
    """
    if isinstance(obj, (float, Decimal)):
        return obj
    elif isinstance(obj, _MISSING_TYPE):
        return None
    elif callable(obj):
        # its a function callable returning a value
        try:
            return obj()
        except:
            pass
    else:
        try:
            return float(obj)
        except (TypeError, ValueError):
            return None

cpdef object to_decimal(object obj):
    """to_decimal.

    Returns a Decimal version of object.
    """
    if obj is None:
        return None
    if isinstance(obj, Decimal):
        return obj
    elif callable(obj):
        # its a function callable returning a value
        try:
            return obj()
        except:
            pass
    else:
        try:
            return Decimal(obj)
        except (TypeError, ValueError):
            return None

TIMEDELTA_RE = re.compile(r"(-)?(\d{1,3}):(\d{1,2}):(\d{1,2})(?:.(\d{1,6}))?")

cpdef int _convert_second_fraction(s):
    if not s:
        return 0
    # Pad zeros to ensure the fraction length in microseconds
    s = s.ljust(6, "0")
    return int(s[:6])

cpdef datetime.timedelta to_timedelta(object obj):
    if isinstance(obj, (bytes, bytearray)):
        obj = obj.decode("ascii")

    m = TIMEDELTA_RE.match(obj)
    if not m:
        return obj

    try:
        groups = list(m.groups())
        groups[-1] = _convert_second_fraction(groups[-1])
        negate = -1 if groups[0] else 1
        hours, minutes, seconds, microseconds = groups[1:]
        tdelta = (
                datetime.timedelta(
                    hours=int(hours),
                    minutes=int(minutes),
                    seconds=int(seconds),
                    microseconds=int(microseconds),
                )
                * negate
        )
        return tdelta
    except ValueError:
        raise ValueError(
            f"Invalid timedelta Object: {obj}"
        )

TIME_RE = re.compile(r"(\d{1,2}):(\d{1,2}):(\d{1,2})(?:.(\d{1,6}))?")

cpdef object to_time(object obj):
    """to_time.

     Returns obj converted to datetime.time.
    """
    if obj is None:
        return None
    if isinstance(obj, datetime.time):
        return obj
    elif callable(obj):
        # its a function callable returning a value
        try:
            return obj()
        except:
            pass
    else:
        try:
            return datetime.time(*map(int, obj.split(':')))
        except (ValueError, TypeError):
            pass
        m = TIME_RE.match(obj)
        if not m:
            return obj
        try:
            groups = list(m.groups())
            groups[-1] = _convert_second_fraction(groups[-1])
            hours, minutes, seconds, microseconds = groups
            return datetime.time(
                hour=int(hours),
                minute=int(minutes),
                second=int(seconds),
                microsecond=int(microseconds),
            )
        except (TypeError, ValueError) as e:
            raise ValueError(
                f"Invalid Time/Timestamp Object {obj}: {e}"
            )


cdef object strtobool(str val):
    """Convert a string representation of truth to true (1) or false (0).

    True values are 'y', 'yes', 't', 'true', 'on', and '1'; false values
    are 'n', 'no', 'f', 'false', 'off', and '0'.  Raises ValueError if
    'val' is anything else.
    """
    val = val.lower()
    if val in ('y', 'yes', 't', 'true', 'on', '1'):
        return True
    elif val in ('n', 'no', 'f', 'false', 'off', '0'):
        return False
    else:
        raise ValueError(
            f"Invalid truth value for {val}"
        )

cpdef object to_boolean(object obj):
    """to_boolean.

    Convert and returns any object value to boolean version.
    """
    if obj is None:
        return False
    if isinstance(obj, bool):
        return obj
    if isinstance(obj, (bytes, bytearray)):
        obj = obj.decode("ascii")
    if isinstance(obj, str):
        return strtobool(obj)
    elif callable(obj):
        # its a function callable returning a value
        try:
            return obj()
        except:
            pass
    else:
        return bool(obj)

cpdef object to_object(object obj):
    if obj is None:
        return None
    if isinstance(obj, (list, dict,tuple)):
        return obj
    elif callable(obj):
        # its a function callable returning a value
        try:
            return obj()
        except:
            pass
    elif isinstance(obj, str):
        try:
            return orjson.loads(obj)
        except (TypeError, ValueError):
            return None
    else:
        raise ValueError(
            f"Can't convert invalid data {obj} to Object"
        )

cdef dict encoders = {
    UUID: to_uuid,
    bool: to_boolean,
    int: to_integer,
    float: to_float,
    datetime.date: to_date,
    datetime.datetime: to_datetime,
    datetime.timedelta: to_timedelta,
    datetime.time: to_time,
    Decimal: to_decimal,
    dict: to_object,
    list: to_object,
    tuple: to_object
}

def parse_type(object T, object data, object encoder = None):
    if hasattr(T, '__module__') and T.__module__ == 'typing':
        args = None
        try:
            args = T.__args__
        except AttributeError:
            pass
        if T._name == 'Dict' and isinstance(data, dict):
            if args:
                return {k: parse_type(T.__args__[1], v) for k, v in data.items()}
        elif T._name == 'List':
            if not isinstance(data, (list, tuple)):
                data = [data]
            arg_type = args[0]
            if arg_type.__module__ == 'typing': # nested typing
                try:
                    t = arg_type.__args__[0]
                    if is_dataclass(t):
                        result = []
                        for x in data:
                            if isinstance(x, dict):
                                result.append(t(**x))
                            elif isinstance(x, (list, tuple)):
                                result.append(t(*x))
                            else:
                                result.append(t())
                        return result
                    else:
                        return data
                except AttributeError:
                    return data # data -as is-
            elif is_dataclass(arg_type):
                if isinstance(data, list):
                    result = []
                    for d in data:
                        # is already a dataclass:
                        if is_dataclass(d):
                            result.append(d)
                        elif isinstance(d, list):
                            result.append(arg_type(*d))
                        elif isinstance(d, dict):
                            result.append(arg_type(**d))
                        else:
                            result.append(arg_type(d))
                return result
            else:
                result = []
                if is_iterable(data):
                    for item in data:
                        # escalar value:
                        converted_item = parse_type(arg_type, item, encoder)
                        result.append(converted_item)
                    return result
                return data
        elif T._name is None or T._name in ('Optional', 'Union'):
            origin = get_origin(T)
            args = get_args(T)
            # Handling Optional types
            if origin == Union and type(None) in args:
                if data is None:
                    return None
                else:
                    non_none_arg = args[0] if args[1] is type(None) else args[1]
                    return parse_type(non_none_arg, data, encoder)
            try:
                t = args[0]
                if is_dataclass(t):
                    if isinstance(data, dict):
                        data = t(**data)
                    elif isinstance(data, (list, tuple)):
                        data = t(*data)
                    else:
                        ## is already a dataclass, returning
                        return data
                elif callable(t):
                    if t.__module__ == 'typing': # nested typing
                        # there is also a nested typing:
                        if t._name == 'List' and isinstance(data, list):
                            arg = t.__args__[0]
                            if is_dataclass(arg):
                                result = []
                                for x in data:
                                    if isinstance(x, dict):
                                        result.append(arg(**x))
                                    else:
                                        result.append(arg(*x))
                                return result
                        return data
                    else:
                        try:
                            if t == str:
                                return data
                            fn = encoders[t]
                            try:
                                if data is not None:
                                    data = fn(data)
                            except TypeError as ex:
                                pass
                            except (ValueError, RuntimeError) as exc:
                                raise ValueError(
                                    f"Model: Error parsing {T}, {exc}"
                                )
                        except KeyError:
                            logging.warning(
                                f'Unsupported Encoder {t}'
                            )
                            pass
                return data
            except KeyError:
                pass
    else:
        if encoder is not None:
            # using a function encoder:
            try:
                return encoder(data)
            except ValueError as e:
                raise ValueError(
                    f"Error parsing type {T}, {e}"
                )
        elif is_dataclass(T):
            if isinstance(data, dict):
                data = T(**data)
            elif isinstance(data, (list, tuple)):
                data = T(*data)
            else:
                data = T(data)
            return data
        else:
            try:
                conv = encoders[T]
                return conv(data)
            except KeyError:
                pass
            except (TypeError, ValueError) as e:
                raise ValueError(
                    f"Error type {T}: {e}"
                ) from e
            # making last conversion:
            if inspect.isclass(T):
                try:
                    if isinstance(data, dict):
                        data = T(**data)
                    elif isinstance(data, (list, tuple)):
                        data = T(*data)
                    elif isinstance(data, str):
                        data = T(data)
                except (TypeError, ValueError) as e:
                    logging.error(
                        f'Conversion Error {T!r}: {e}'
                    )
                return data
        return data

cpdef object parse_basic(object T, object data, object encoder = None):
    """parse_type.

    Parse a value to primitive types as str or int.
    --- (int, float, str, bool, bytes)
    """
    if T == str:
        return str(data)
    elif T == bytes:
        return bytes(data)

    # Using the encoders for basic types:
    try:
        return encoders[T](data)
    except KeyError:
        pass
    except (TypeError, ValueError) as e:
        raise ValueError(
            f"Encoder Error {T}: {e}"
        ) from e

    # function encoder:
    if encoder and callable(encoder):
        # using a function encoder:
        try:
            return encoder(data)
        except ValueError as e:
            raise ValueError(
                f"Error parsing type {T}, {e}"
            )
