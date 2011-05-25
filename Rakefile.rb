# encoding: UTF-8

require 'rubygems'
require 'rake/rdoctask'
require 'rake/testtask'
require 'rake/gempackagetask'

spec = Gem::Specification.new do |s|
  s.name       = "origami"
  s.version    = "1.0.2"
  s.author     = "Guillaume Delugré"
  s.email      = "guillaume at security-labs dot org"
  s.homepage   = "http://esec-lab.sogeti.com/dotclear/index.php?pages/Origami"
  s.platform   = Gem::Platform::RUBY
  
  s.summary    = "Origami aims at providing a scripting tool to generate and analyze malicious PDF files."
  s.description = <<DESC
This is NOT a PDF rendering library. It aims at providing a scripting tool to generate and analyze malicious PDF files. 
As well, it can be used to create on-the-fly customized PDFs, or to inject (evil) code into already existing documents.

  - Create PDF documents from scratch.
  - Parse existing documents, modify them and recompile them.
  - Explore documents at the object level, going deep into the document structure, uncompressing PDF object streams and desobfuscating names and strings.
  - High-level operations, such as encryption/decryption, signature, file attachments...
  - A GTK interface to quickly browse into the document contents.
  - A set of command-line tools for PDF analysis.
DESC

  s.files             = FileList[
    'README', 'COPYING.LESSER', 'VERSION', "origami.rb", "{origami,bin,tests,walker,templates}/**/*", "bin/shell/.irbrc"
  ].exclude(/\.pdf$/, /\.key$/, /\.crt$/, /\.conf$/).to_a

  s.require_path      = "."
  s.has_rdoc          = false
  s.test_file         = "tests/ts_pdf.rb"
  s.requirements      = "ruby-gtk2 if you plan to run the PDF Walker interface"

  s.bindir            = "bin"
  s.executables       = [ "pdfdecompress", "pdfdecrypt", "pdfencrypt", "pdfmetadata", "pdf2graph", "pdf2ruby", "pdfextract", "pdfcop", "pdfcocoon", "pdfsh", "pdfwalker" ]
end

task :default => [:package]

Rake::GemPackageTask.new(spec) do |pkg|
  pkg.need_tar = true
end

desc "Generate rdoc documentation"
Rake::RDocTask.new("rdoc") do |rdoc|
  rdoc.rdoc_dir = "doc"
  rdoc.title = "Origami"
  rdoc.options << "-U" << "-S" << "-N"
  rdoc.options << "-m" << "Origami::PDF"

  rdoc.rdoc_files.include("origami/**/*.rb")
end

desc "Run the test suite"
Rake::TestTask.new do |t|
 t.verbose = true
 t.libs << "tests" 
 t.test_files = FileList["tests/ts_pdf.rb"]
end

task :clean do
  %x{rm -rf pkg doc}
end
