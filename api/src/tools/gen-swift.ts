import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { parse } from 'yaml';

// Generates the iOS API types (ios/Supermortgage/App/API/Generated.swift) and the example JSON the
// iOS unit tests decode (ios/SupermortgageTests/APIExamples.swift) from openapi.yaml's components.

interface Schema {
  $ref?: string;
  type?: string | string[];
  format?: string;
  enum?: string[];
  properties?: Record<string, Schema>;
  required?: string[];
  items?: Schema;
  anyOf?: Schema[];
  oneOf?: Schema[];
  description?: string;
  examples?: unknown[];
  nullable?: boolean;
}

const specPath = fileURLToPath(new URL('../../openapi.yaml', import.meta.url));
const typesPath = fileURLToPath(new URL('../../../ios/Supermortgage/App/API/Generated.swift', import.meta.url));
const examplesPath = fileURLToPath(new URL('../../../ios/SupermortgageTests/APIExamples.swift', import.meta.url));

const spec = parse(readFileSync(specPath, 'utf8')) as { components?: { schemas?: Record<string, Schema> } };
const all = spec.components?.schemas ?? {};
// The provider registers an `<Name>Input` twin of every schema for request bodies; the shapes are
// identical here, so the Swift types come from the output schemas only.
const schemas = Object.fromEntries(
  Object.entries(all).filter(([name]) => !(name.endsWith('Input') && name.slice(0, -'Input'.length) in all)),
);

function refName(ref: string): string {
  const name = ref.split('/').pop();
  if (!name) throw new Error(`bad $ref ${ref}`);
  return name;
}

function swiftType(schema: Schema): { type: string; nullable: boolean } {
  if (schema.$ref) return { type: refName(schema.$ref), nullable: false };
  const variants = schema.anyOf ?? schema.oneOf;
  if (variants) {
    const nonNull = variants.filter((v) => v.type !== 'null');
    const nullable = nonNull.length !== variants.length;
    const only = nonNull[0];
    if (nonNull.length === 1 && only) {
      const inner = swiftType(only);
      return { type: inner.type, nullable: nullable || inner.nullable };
    }
    throw new Error(`unsupported union: ${JSON.stringify(schema)}`);
  }
  const types = Array.isArray(schema.type) ? schema.type : schema.type ? [schema.type] : [];
  const nullable = types.includes('null') || schema.nullable === true;
  const primary = types.find((t) => t !== 'null');
  switch (primary) {
    case 'string':
      return { type: 'String', nullable };
    case 'integer':
      return { type: 'Int', nullable };
    case 'number':
      return { type: 'Double', nullable };
    case 'boolean':
      return { type: 'Bool', nullable };
    case 'array': {
      const inner = swiftType(schema.items ?? {});
      return { type: `[${inner.type}${inner.nullable ? '?' : ''}]`, nullable };
    }
    default:
      throw new Error(`unsupported schema: ${JSON.stringify(schema)}`);
  }
}

function caseName(value: string): string {
  const camel = value.replace(/[^A-Za-z0-9]+(.)?/g, (_m, c: string | undefined) => (c ? c.toUpperCase() : ''));
  return camel.charAt(0).toLowerCase() + camel.slice(1);
}

function doc(text: string | undefined, indent: string): string {
  return text ? `${indent}/// ${text.replace(/\s+/g, ' ').trim()}\n` : '';
}

let swift = `// Generated from api/openapi.yaml by api/src/tools/gen-swift.ts. Do not edit; run \`npm run gen:swift\` in api/.

import Foundation

/// The API's request and response types, named as the components of openapi.yaml.
enum API {
`;
let count = 0;
for (const [name, schema] of Object.entries(schemas)) {
  if (schema.enum) {
    swift += doc(schema.description, '    ');
    swift += `    enum ${name}: String, Codable, Equatable, CaseIterable {\n`;
    for (const value of schema.enum) {
      swift += `        case ${caseName(value)} = "${value}"\n`;
    }
    swift += `    }\n\n`;
  } else if (schema.type === 'object' || schema.properties) {
    const required = new Set(schema.required ?? []);
    swift += doc(schema.description, '    ');
    swift += `    struct ${name}: Codable, Equatable {\n`;
    for (const [prop, propSchema] of Object.entries(schema.properties ?? {})) {
      const { type, nullable } = swiftType(propSchema);
      const optional = nullable || !required.has(prop);
      swift += doc(propSchema.description, '        ');
      swift += `        var ${prop}: ${type}${optional ? '?' : ''}\n`;
    }
    swift += `    }\n\n`;
  } else {
    throw new Error(`cannot generate ${name}: ${JSON.stringify(schema)}`);
  }
  count += 1;
}
swift = `${swift.trimEnd()}\n}\n`;
writeFileSync(typesPath, swift);

let examples = `// Generated from the examples in api/openapi.yaml by api/src/tools/gen-swift.ts. Do not edit.

import Foundation

/// Example JSON for the API's response types, exactly as openapi.yaml documents them.
enum APIExamples {
`;
for (const [name, schema] of Object.entries(schemas)) {
  if (!schema.examples || schema.examples.length === 0) continue;
  examples += `    /// components.schemas.${name}\n`;
  examples += `    static let ${caseName(name)}: [String] = [\n`;
  for (const example of schema.examples) {
    const json = JSON.stringify(example, null, 2)
      .split('\n')
      .map((line) => `        ${line}`)
      .join('\n');
    examples += `        #"""\n${json}\n        """#,\n`;
  }
  examples += `    ]\n`;
}
examples += `}\n`;
writeFileSync(examplesPath, examples);
console.log(`wrote ${count} types to ${typesPath} and the examples to ${examplesPath}`);
