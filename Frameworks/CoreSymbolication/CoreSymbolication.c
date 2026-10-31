/*
 * CoreSymbolication -- compatibility surface for stock macOS binaries.
 *
 * Present so dyld can load an application that links it (Firefox's XUL does).
 * The staged bundle imports no symbols from it, so this library exports none;
 * a missing library at load time is what actually stops the application.
 */
