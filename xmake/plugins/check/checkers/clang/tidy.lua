--!A cross-platform build utility based on Lua
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--
-- Copyright (C) 2015-present, TBOOX Open Source Group.
--
-- @author      ruki
-- @file        tidy.lua
--

-- imports
import("core.base.option")
import("core.base.task")
import("core.project.config")
import("core.project.project")
import("lib.detect.find_tool")
import("private.async.runjobs")
import("private.action.require.impl.packagenv")
import("private.action.require.impl.install_packages")

-- the clang.tidy options
local options = {
    {"l", "list",   "k",   nil,   "Show the clang-tidy checks list."},
    {'j', "jobs",   "kv", tostring(os.default_njob()),
                                  "Set the number of parallel check jobs."},
    {nil, "checks", "kv",  nil,   "Set the given checks.",
                                  "e.g.",
                                  "    - xmake check clang.tidy --checks=\"*\""},
    {nil, "target", "v",   nil,   "Check the sourcefiles of the given target.",
                                  ".e.g",
                                  "    - xmake check clang.tidy",
                                  "    - xmake check clang.tidy [target]"}
}

-- show checks list
function _show_list(clang_tidy)
    os.execv(clang_tidy, {"-list-checks"})
end

-- add sourcefiles in target
function _add_target_files(sourcefiles, target)
    table.join2(sourcefiles, (target:sourcefiles()))
end

-- check sourcefile
function _check_sourcefile(clang_tidy, sourcefile, opt)
    opt = opt or {}
    local argv = {}
    if opt.checks then
        table.insert(argv, "-checks=" .. opt.checks)
    end
    if opt.compdbfile then
        table.insert(argv, "-p")
        table.insert(argv, opt.compdbfile)
    end
    table.insert(argv, sourcefile)
    os.execv(clang_tidy, argv)
end

-- do check
function _check(clang_tidy, opt)
    opt = opt or {}

    -- generate compile_commands.json first
    local filename = "compile_commands.json"
    local filepath = filename
    if not os.isfile(filepath) then
        local outputdir = os.tmpfile() .. ".dir"
        filepath = outputdir and path.join(outputdir, filename) or filename
        task.run("project", {quiet = true, kind = "compile_commands", outputdir = outputdir})
    end
    opt.compdbfile = filepath

    -- get sourcefiles
    local sourcefiles = {}
    local targetname = opt.target
    if targetname then
        _add_target_files(sourcefiles, project.target(targetname))
    else
        for _, target in ipairs(project.ordertargets()) do
            _add_target_files(sourcefiles, target)
        end
    end

    -- check files
    local jobs = tonumber(opt.jobs or "1")
    runjobs("check_files", function (index)
        local sourcefile = sourcefiles[index]
        if sourcefile then
            _check_sourcefile(clang_tidy, sourcefile, opt)
        end
    end, {total = #sourcefiles,
          comax = jobs,
          isolate = true})
end

function main(argv)

    -- parse arguments
    local args = option.parse(argv or {}, options, "Use clang-tidy to check project code."
                                           , ""
                                           , "Usage: xmake check clang.tidy [options]")

    -- enter the environments of llvm
    local oldenvs = packagenv.enter("llvm")

    -- find clang-tidy
    local packages = {}
    local clang_tidy = find_tool("clang-tidy")
    if not clang_tidy then
        table.join2(packages, install_packages("llvm"))
    end

    -- enter the environments of installed packages
    for _, instance in ipairs(packages) do
        instance:envs_enter()
    end

    -- we need force to detect and flush detect cache after loading all environments
    if not clang_tidy then
        clang_tidy = find_tool("clang-tidy", {force = true})
    end
    assert(clang_tidy, "clang-tidy not found!")

    -- list checks
    if args.list then
        _show_list(clang_tidy.program)
    else
        _check(clang_tidy.program, args)
    end

    -- done
    os.setenvs(oldenvs)
end
