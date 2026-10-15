# Multipart form uploads

ESP exposes text fields in a `multipart/form-data` request through
`Request.Form` and uploaded files through `Request.Files`. Each uploaded file
provides its filename, content type, content length and an input stream for
reading the original bytes. Empty files are retained.

A multipart delimiter must start at the beginning of the request body or after
CRLF, and must occupy a complete line. After the boundary value, an ordinary
delimiter ends with CRLF; a closing delimiter has `--` followed by CRLF or the
end of the body. Spaces and tabs may pad the end of either delimiter line.

Boundary-like bytes inside an uploaded file remain part of its content. For
example, with boundary `ESP-boundary-AaB03x`, the bytes
`abc\r\n--ESP-boundary-AaB03x-not-a-boundary` are preserved in full.

Clients must choose a boundary that does not occur as an actual delimiter in
the uploaded content. An exact delimiter line separates parts and cannot also
represent file data within that multipart request.
