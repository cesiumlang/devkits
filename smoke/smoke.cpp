// Smoke test of a devkit's LLVM and LLD libraries: what the Cesium compiler
// will do with them, in miniature. Parses LLVM IR through the C API, emits an
// object file for one target per architecture family, and links with
// in-process LLD through the shim of ADR 0001 (cesiumlang/cesium#4).
//
// usage: smoke <output directory>
#include "lld/Common/Driver.h"
#include "llvm-c/Core.h"
#include "llvm-c/IRReader.h"
#include "llvm-c/Target.h"
#include "llvm-c/TargetMachine.h"
#include "llvm/Support/raw_ostream.h"

#include <cstdio>
#include <cstring>
#include <string>

LLD_HAS_DRIVER(elf)
LLD_HAS_DRIVER(coff)
LLD_HAS_DRIVER(macho)
LLD_HAS_DRIVER(wasm)

static int lld_link(int argc, const char **argv) {
  const lld::DriverDef drivers[] = {
      {lld::Gnu, &lld::elf::link},
      {lld::WinLink, &lld::coff::link},
      {lld::Darwin, &lld::macho::link},
      {lld::Wasm, &lld::wasm::link},
  };
  lld::Result r = lld::lldMain(llvm::ArrayRef<const char *>(argv, argc),
                               llvm::outs(), llvm::errs(), drivers);
  return r.retCode;
}

static const char ir[] =
    "define i32 @answer(i32 %x) {\n"
    "  %y = add i32 %x, 42\n"
    "  ret i32 %y\n"
    "}\n";

// Emit `ir` as an object file for a triple. Returns 0 on success.
static int emit(const char *triple, const std::string &path) {
  LLVMContextRef ctx = LLVMContextCreate();
  LLVMMemoryBufferRef buf =
      LLVMCreateMemoryBufferWithMemoryRangeCopy(ir, std::strlen(ir), "smoke");
  LLVMModuleRef mod = nullptr;
  char *err = nullptr;
  if (LLVMParseIRInContext(ctx, buf, &mod, &err)) {
    std::fprintf(stderr, "%s: parse: %s\n", triple, err);
    return 1;
  }
  LLVMTargetRef target = nullptr;
  if (LLVMGetTargetFromTriple(triple, &target, &err)) {
    std::fprintf(stderr, "%s: no target: %s\n", triple, err);
    return 1;
  }
  LLVMTargetMachineRef tm = LLVMCreateTargetMachine(
      target, triple, "", "", LLVMCodeGenLevelDefault, LLVMRelocPIC,
      LLVMCodeModelDefault);
  LLVMSetTarget(mod, triple);
  if (LLVMTargetMachineEmitToFile(tm, mod, path.c_str(), LLVMObjectFile,
                                  &err)) {
    std::fprintf(stderr, "%s: emit: %s\n", triple, err);
    return 1;
  }
  LLVMDisposeTargetMachine(tm);
  LLVMDisposeModule(mod);
  LLVMContextDispose(ctx);
  std::printf("emitted %s\n", path.c_str());
  return 0;
}

int main(int argc, char **argv) {
  if (argc != 2) {
    std::fprintf(stderr, "usage: smoke <output directory>\n");
    return 2;
  }
  std::string dir = argv[1];

  LLVMInitializeAllTargetInfos();
  LLVMInitializeAllTargets();
  LLVMInitializeAllTargetMCs();
  LLVMInitializeAllAsmPrinters();
  LLVMInitializeAllAsmParsers();

  // every target of devkit.json must be present
  static const char *const lookups[] = {
      "x86_64-unknown-linux-musl", "aarch64-unknown-linux-musl",
      "armv7-unknown-none-eabi",   "powerpc-unknown-none-eabi",
      "spirv64-unknown-unknown",   "wasm32-unknown-wasi",
  };
  for (const char *t : lookups) {
    LLVMTargetRef target = nullptr;
    char *err = nullptr;
    if (LLVMGetTargetFromTriple(t, &target, &err)) {
      std::fprintf(stderr, "%s: no target: %s\n", t, err);
      return 1;
    }
  }

  std::string elf = dir + "/answer-elf.o";
  std::string coff = dir + "/answer-coff.obj";
  std::string wasm = dir + "/answer-wasm.o";
  if (emit("x86_64-unknown-linux-musl", elf)) return 1;
  if (emit("x86_64-pc-windows-msvc", coff)) return 1;
  if (emit("wasm32-unknown-wasi", wasm)) return 1;
  if (emit("aarch64-unknown-linux-musl", dir + "/answer-aarch64.o")) return 1;
  if (emit("armv7-unknown-none-eabi", dir + "/answer-arm.o")) return 1;
  if (emit("powerpc-unknown-none-eabi", dir + "/answer-ppc.o")) return 1;

  std::string elf_out = dir + "/answer-elf";
  const char *elf_args[] = {"ld.lld", "-e", "answer", elf.c_str(),
                            "-o",     elf_out.c_str()};
  if (lld_link(6, elf_args)) return 1;
  std::printf("linked %s\n", elf_out.c_str());

  std::string coff_out = "/out:" + dir + "/answer-coff.exe";
  const char *coff_args[] = {"lld-link",        "/entry:answer",
                             "/subsystem:console", "/nodefaultlib",
                             coff.c_str(),      coff_out.c_str()};
  if (lld_link(6, coff_args)) return 1;
  std::printf("linked %s\n", coff_out.c_str());

  std::string wasm_out = dir + "/answer.wasm";
  const char *wasm_args[] = {"wasm-ld",       "--no-entry", "--export=answer",
                             wasm.c_str(),    "-o",         wasm_out.c_str()};
  if (lld_link(6, wasm_args)) return 1;
  std::printf("linked %s\n", wasm_out.c_str());

  std::printf("llvm and lld ok\n");
  return 0;
}
