#!/usr/bin/env python3

import gzip
import json
import os
import requests
import shutil

test_url = "https://github.com/virtualxt/8088/raw/main/v2/"
index_filename = "metadata.json"
test_filename = "../opcodes.odin"

test_header = """// This file is generated!
package tests

import "core:testing"
"""

test_case = """
@(test)
opcode_{sym_name} :: proc(t: ^testing.T) {{
	run_opcode_tests(t, "src/tests/testdata/{file_name}.json", transmute(Flags)u16({flags_mask}))
}}
"""

skip_opcodes = (
    # POP CS / Extended
    0xF,
    
    # Wait and Halt instruction
    0x9B, 0xF4,

    # BUG: IDIV
    (0xF6, 7), (0xF7, 7),
)

def check_and_download(filename):
    if not os.path.exists(filename):
        print("Downloading: " + filename)

        url = test_url + filename
        resp = requests.get(url)
        if resp.status_code != requests.codes.ok:
            print("Could not download: " + filename)
            return False

        with open(filename, "wb") as f:
            f.write(resp.content)

    return True

def skip_opcode(name):
    opcode = int(name[:2], 16)

    for op in skip_opcodes:
        if isinstance(op, tuple):
            if op[0] == opcode and int(name[3:]) == op[1]:
                return True
        elif op == opcode:
            return True

    return False

def unpack_test(name, status):
    if skip_opcode(name):
        return False

    # TODO: Test aliases?
    if status in ["undefined", "prefix", "fpu", "undocumented", "alias"]:
        return False

    json_name = name + ".json"
    gz_name = json_name + ".gz"
    
    if os.path.exists(json_name):
        return True
    
    if not check_and_download(gz_name):
        return False

    print("Unpacking: " + gz_name)
    with gzip.open(gz_name, "rb") as f_in:
        with open(json_name, "wb") as f_out:
            shutil.copyfileobj(f_in, f_out)

    return True

def gen_test(name, data):
    mask = 0xFFFF
    if "flags-mask" in data:
        mask = data["flags-mask"]

    with open(test_filename, "a") as f:
        f.write(test_case.format(sym_name = name.replace(".", "_"), file_name = name, flags_mask = mask))

####################### Start #######################

if check_and_download(index_filename):
    index_file = json.loads(open(index_filename, "r").read())

    with open(test_filename, "w") as f:
        f.write(test_header)

    for opcode,data in index_file["opcodes"].items():
        # This data is "broken" and should not be tuple encoded.
        if opcode in ["8F", "C6", "C7"]:
            data = data["reg"]["0"]
        
        if "reg" in data:
            for reg,rd in data["reg"].items():
                name = "{}.{}".format(opcode, reg)
                if unpack_test(name, rd["status"]):
                    gen_test(name, rd)
        else:
            if unpack_test(opcode, data["status"]):
                gen_test(opcode, data)
