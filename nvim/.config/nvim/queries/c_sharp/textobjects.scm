;; Object initializer block
(initializer_expression) @initializer.outer
(initializer_expression) @initializer.inner

;; Methods / "functions"
(method_declaration
  body: (block) @function.inner) @function.outer

(constructor_declaration
  body: (block) @function.inner) @function.outer

(local_function_statement
  body: (block) @function.inner) @function.outer

;; Types
(class_declaration
  body: (declaration_list) @class.inner) @class.outer

(struct_declaration
  body: (declaration_list) @class.inner) @class.outer

(interface_declaration
  body: (declaration_list) @class.inner) @class.outer

(record_declaration
  body: (declaration_list) @class.inner) @class.outer
