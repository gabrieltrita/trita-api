SimpleCov.start do
  enable_coverage :branch
  cover "{app,lib}/**/*.rb"

  coverage :line, minimum: 100
  coverage :branch, minimum: 100
end
