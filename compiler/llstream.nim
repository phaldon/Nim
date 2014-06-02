#
#
#           The Nimrod Compiler
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Low-level streams for high performance.

import 
  strutils

when not defined(windows) and defined(useGnuReadline):
  import rdstdin

type 
  TLLStreamKind* = enum       # enum of different stream implementations
    llsNone,                  # null stream: reading and writing has no effect
    llsString,                # stream encapsulates a string
    llsFile,                  # stream encapsulates a file
    llsStdIn                  # stream encapsulates stdin
  TLLStream* = object of TObject
    kind*: TLLStreamKind # accessible for low-level access (lexbase uses this)
    f*: TFile
    s*: string
    rd*, wr*: int             # for string streams
    lineOffset*: int          # for fake stdin line numbers
  
  PLLStream* = ref TLLStream

proc llStreamOpen*(data: string): PLLStream
proc llStreamOpen*(f: var TFile): PLLStream
proc llStreamOpen*(filename: string, mode: TFileMode): PLLStream
proc llStreamOpen*(): PLLStream
proc llStreamOpenStdIn*(): PLLStream
proc llStreamClose*(s: PLLStream)
proc llStreamRead*(s: PLLStream, buf: pointer, bufLen: int): int
proc llStreamReadLine*(s: PLLStream, line: var string): bool
proc llStreamReadAll*(s: PLLStream): string
proc llStreamWrite*(s: PLLStream, data: string)
proc llStreamWrite*(s: PLLStream, data: char)
proc llStreamWrite*(s: PLLStream, buf: pointer, buflen: int)
proc llStreamWriteln*(s: PLLStream, data: string)
# implementation

proc llStreamOpen(data: string): PLLStream = 
  new(result)
  result.s = data
  result.kind = llsString

proc llStreamOpen(f: var TFile): PLLStream = 
  new(result)
  result.f = f
  result.kind = llsFile

proc llStreamOpen(filename: string, mode: TFileMode): PLLStream = 
  new(result)
  result.kind = llsFile
  if not open(result.f, filename, mode): result = nil
  
proc llStreamOpen(): PLLStream = 
  new(result)
  result.kind = llsNone

proc llStreamOpenStdIn(): PLLStream = 
  new(result)
  result.kind = llsStdIn
  result.s = ""
  result.lineOffset = -1

proc llStreamClose(s: PLLStream) = 
  case s.kind
  of llsNone, llsString, llsStdIn: 
    discard
  of llsFile: 
    close(s.f)

when not defined(readLineFromStdin): 
  # fallback implementation:
  proc readLineFromStdin(prompt: string, line: var string): bool =
    stdout.write(prompt)
    result = readLine(stdin, line)
    if not result:
      stdout.write("\n")
      quit(0)

proc endsWith*(x: string, s: set[char]): bool =
  var i = x.len-1
  while i >= 0 and x[i] == ' ': dec(i)
  if i >= 0 and x[i] in s:
    result = true

const 
  LineContinuationOprs = {'+', '-', '*', '/', '\\', '<', '>', '!', '?', '^',
                          '|', '%', '&', '$', '@', '~', ','}
  AdditionalLineContinuationOprs = {'#', ':', '='}

proc endsWithOpr*(x: string): bool =
  # also used by the standard template filter:
  result = x.endsWith(LineContinuationOprs)

proc continueLine(line: string, inTripleString: bool): bool {.inline.} =
  result = inTripleString or
      line[0] == ' ' or
      line.endsWith(LineContinuationOprs+AdditionalLineContinuationOprs)

proc countTriples(s: string): int =
  var i = 0
  while i < s.len:
    if s[i] == '"' and s[i+1] == '"' and s[i+2] == '"':
      inc result
      inc i, 2
    inc i

proc llReadFromStdin(s: PLLStream, buf: pointer, bufLen: int): int =
  s.s = ""
  s.rd = 0
  var line = newStringOfCap(120)
  var triples = 0
  while readLineFromStdin(if s.s.len == 0: ">>> " else: "... ", line): 
    add(s.s, line)
    add(s.s, "\n")
    inc triples, countTriples(line)
    if not continueLine(line, (triples and 1) == 1): break
  inc(s.lineOffset)
  result = min(bufLen, len(s.s) - s.rd)
  if result > 0: 
    copyMem(buf, addr(s.s[s.rd]), result)
    inc(s.rd, result)

proc llStreamRead(s: PLLStream, buf: pointer, bufLen: int): int = 
  case s.kind
  of llsNone: 
    result = 0
  of llsString: 
    result = min(bufLen, len(s.s) - s.rd)
    if result > 0: 
      copyMem(buf, addr(s.s[0 + s.rd]), result)
      inc(s.rd, result)
  of llsFile: 
    result = readBuffer(s.f, buf, bufLen)
  of llsStdIn: 
    result = llReadFromStdin(s, buf, bufLen)
  
proc llStreamReadLine(s: PLLStream, line: var string): bool =
  setLen(line, 0)
  case s.kind
  of llsNone:
    result = true
  of llsString:
    while s.rd < len(s.s):
      case s.s[s.rd]
      of '\x0D':
        inc(s.rd)
        if s.s[s.rd] == '\x0A': inc(s.rd)
        break
      of '\x0A':
        inc(s.rd)
        break
      else:
        add(line, s.s[s.rd])
        inc(s.rd)
    result = line.len > 0 or s.rd < len(s.s)
  of llsFile:
    result = readLine(s.f, line)
  of llsStdIn:
    result = readLine(stdin, line)
    
proc llStreamWrite(s: PLLStream, data: string) = 
  case s.kind
  of llsNone, llsStdIn: 
    discard
  of llsString: 
    add(s.s, data)
    inc(s.wr, len(data))
  of llsFile: 
    write(s.f, data)
  
proc llStreamWriteln(s: PLLStream, data: string) = 
  llStreamWrite(s, data)
  llStreamWrite(s, "\n")

proc llStreamWrite(s: PLLStream, data: char) = 
  var c: char
  case s.kind
  of llsNone, llsStdIn: 
    discard
  of llsString: 
    add(s.s, data)
    inc(s.wr)
  of llsFile: 
    c = data
    discard writeBuffer(s.f, addr(c), sizeof(c))

proc llStreamWrite(s: PLLStream, buf: pointer, buflen: int) = 
  case s.kind
  of llsNone, llsStdIn: 
    discard
  of llsString: 
    if buflen > 0: 
      setLen(s.s, len(s.s) + buflen)
      copyMem(addr(s.s[0 + s.wr]), buf, buflen)
      inc(s.wr, buflen)
  of llsFile: 
    discard writeBuffer(s.f, buf, buflen)
  
proc llStreamReadAll(s: PLLStream): string = 
  const 
    bufSize = 2048
  case s.kind
  of llsNone, llsStdIn: 
    result = ""
  of llsString: 
    if s.rd == 0: result = s.s
    else: result = substr(s.s, s.rd)
    s.rd = len(s.s)
  of llsFile: 
    result = newString(bufSize)
    var bytes = readBuffer(s.f, addr(result[0]), bufSize)
    var i = bytes
    while bytes == bufSize: 
      setLen(result, i + bufSize)
      bytes = readBuffer(s.f, addr(result[i + 0]), bufSize)
      inc(i, bytes)
    setLen(result, i)
