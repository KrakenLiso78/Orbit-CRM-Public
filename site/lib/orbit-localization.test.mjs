import test from 'node:test';
import assert from 'node:assert/strict';
import { localizeValue } from './orbit-localization.mjs';
void test('stored Spanish task states and English lifecycle events localize without changing their identity', () => {
  assert.equal(localizeValue('1-En curso','en'),'In progress');
  assert.equal(localizeValue('rejected','es'),'Rechazada');
  assert.equal(localizeValue('Contacto hecho','en'),'Contact made');
  assert.equal(localizeValue('job_discovery','es'),'Búsqueda de empleo');
  assert.equal(localizeValue('Rechazada','en'),'Rejected');
  assert.equal(localizeValue('Cerrada','en'),'Closed');
  assert.equal(localizeValue('Screening','es'),'Evaluación inicial');
});
void test('unknown values and original evidence remain verbatim', () => {
  for(const lang of ['es','en']) {
    assert.equal(localizeValue('Original source: candidate reports rejection','en'),'Original source: candidate reports rejection');
    assert.equal(localizeValue('New unknown provider status',lang),'New unknown provider status');
  }
});
