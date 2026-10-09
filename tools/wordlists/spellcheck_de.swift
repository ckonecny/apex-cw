import AppKit
let c = NSSpellChecker.shared
func ok(_ w:String)->Bool{ c.checkSpelling(of: w, startingAt: 0, language: "de", wrap: false, inSpellDocumentWithTag: 0, wordCount: nil).location == NSNotFound }
while let l = readLine() { let w=l.split(separator:" ")[0]; let s=String(w)
  if ok(s) || ok(s.prefix(1).uppercased()+s.dropFirst()) { print(l) } }
