import { readFileSync } from 'node:fs';
import { test, before, after, beforeEach } from 'node:test';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import {
  doc, setDoc, updateDoc, deleteDoc, getDoc, getDocs, collection, writeBatch,
  serverTimestamp, increment, arrayRemove, Timestamp,
} from 'firebase/firestore';

let env;
const now = serverTimestamp;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'nido-rules-test',
    firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'), host: '127.0.0.1', port: 8181 },
  });
});
after(() => env.cleanup());
beforeEach(() => env.clearFirestore());

const alice = () => env.authenticatedContext('alice').firestore();
const bob = () => env.authenticatedContext('bob').firestore();
const anon = () => env.unauthenticatedContext().firestore();

const account = (o = {}) => ({
  name: 'Banco', type: 'bank', institution: '', balanceCents: 1000, createdAt: now(), updatedAt: now(), ...o,
});
const movement = (o = {}) => ({
  kind: 'expense', amountCents: 500, accountId: 'acc1', toAccountId: null, category: 'food', note: '',
  date: Timestamp.fromDate(new Date('2026-10-05')), createdAt: now(), updatedAt: now(), ...o,
});
const goal = (o = {}) => ({
  name: 'Colchón', targetCents: 100000, savedCents: 0, accountIds: [], deadline: null,
  createdAt: now(), updatedAt: now(), ...o,
});

test('el dueño crea, lee, actualiza y borra su cuenta', async () => {
  const db = alice();
  const ref = doc(db, 'users/alice/accounts/acc1');
  await assertSucceeds(setDoc(ref, account()));
  await assertSucceeds(getDoc(ref));
  await assertSucceeds(updateDoc(ref, { name: 'Otro', type: 'savings', institution: 'ING', balanceCents: -50, updatedAt: now() }));
  await assertSucceeds(deleteDoc(ref));
});

test('nadie más puede leer ni escribir los datos de alice', async () => {
  await assertSucceeds(setDoc(doc(alice(), 'users/alice/accounts/acc1'), account()));
  await assertFails(getDoc(doc(bob(), 'users/alice/accounts/acc1')));
  await assertFails(getDocs(collection(bob(), 'users/alice/accounts')));
  await assertFails(setDoc(doc(bob(), 'users/alice/accounts/acc2'), account()));
  await assertFails(getDoc(doc(anon(), 'users/alice/accounts/acc1')));
});

test('valida la forma de las cuentas', async () => {
  const ref = doc(alice(), 'users/alice/accounts/x');
  await assertFails(setDoc(ref, account({ type: 'lambo' })));
  await assertFails(setDoc(ref, account({ name: '' })));
  await assertFails(setDoc(ref, account({ balanceCents: 10.5 })));
  await assertFails(setDoc(ref, account({ extra: true })));
  await assertFails(setDoc(ref, account({ createdAt: Timestamp.fromDate(new Date('2020-01-01')) })));
});

test('createdAt no se puede cambiar', async () => {
  const ref = doc(alice(), 'users/alice/accounts/acc1');
  await setDoc(ref, account());
  await assertFails(updateDoc(ref, { createdAt: Timestamp.fromDate(new Date('2020-01-01')), updatedAt: now() }));
  await assertFails(updateDoc(ref, { name: 'Sin updatedAt' }));
});

test('batch de movimiento con increment de saldos (como la app)', async () => {
  const db = alice();
  await setDoc(doc(db, 'users/alice/accounts/acc1'), account());
  await setDoc(doc(db, 'users/alice/accounts/acc2'), account({ name: 'Tarjeta', type: 'creditCard', balanceCents: 0 }));
  const b = writeBatch(db);
  b.set(doc(db, 'users/alice/movements/m1'), movement({ kind: 'transfer', accountId: 'acc1', toAccountId: 'acc2', category: 'transfer' }));
  b.update(doc(db, 'users/alice/accounts/acc1'), { balanceCents: increment(-500), updatedAt: now() });
  b.update(doc(db, 'users/alice/accounts/acc2'), { balanceCents: increment(-500), updatedAt: now() });
  await assertSucceeds(b.commit());
  const acc1 = await getDoc(doc(db, 'users/alice/accounts/acc1'));
  if (acc1.data().balanceCents !== 500) throw new Error('saldo inesperado');
});

test('valida los movimientos', async () => {
  const ref = doc(alice(), 'users/alice/movements/m1');
  await assertSucceeds(setDoc(ref, movement()));
  await assertFails(setDoc(doc(alice(), 'users/alice/movements/m2'), movement({ amountCents: 0 })));
  await assertFails(setDoc(doc(alice(), 'users/alice/movements/m3'), movement({ amountCents: -5 })));
  await assertFails(setDoc(doc(alice(), 'users/alice/movements/m4'), movement({ kind: 'robo' })));
  await assertFails(setDoc(doc(alice(), 'users/alice/movements/m5'), movement({ kind: 'transfer', toAccountId: null })));
  await assertFails(setDoc(doc(alice(), 'users/alice/movements/m6'), movement({ kind: 'transfer', toAccountId: 'acc1' })));
  await assertFails(setDoc(doc(alice(), 'users/alice/movements/m7'), movement({ toAccountId: 'acc2' })));
  await assertFails(setDoc(doc(alice(), 'users/alice/movements/m8'), movement({ note: 'x'.repeat(121) })));
  await assertFails(setDoc(doc(alice(), 'users/alice/movements/m9'), movement({ date: '2026-10-05' })));
  // La app actualiza todos los campos menos createdAt.
  const { createdAt, ...fields } = movement({ amountCents: 900 });
  await assertSucceeds(updateDoc(ref, fields));
});

test('objetivos: crear, aportar, desvincular y borrar', async () => {
  const db = alice();
  const ref = doc(db, 'users/alice/goals/g1');
  await assertSucceeds(setDoc(ref, goal({ accountIds: ['acc1'], deadline: Timestamp.fromDate(new Date('2027-10-01')) })));
  await assertSucceeds(updateDoc(ref, { savedCents: increment(2500), updatedAt: now() }));
  await assertSucceeds(updateDoc(ref, { accountIds: arrayRemove('acc1'), updatedAt: now() }));
  await assertFails(setDoc(doc(db, 'users/alice/goals/g2'), goal({ targetCents: 0 })));
  await assertFails(setDoc(doc(db, 'users/alice/goals/g3'), goal({ deadline: 'mañana' })));
  await assertSucceeds(deleteDoc(ref));
});

test('fotos mensuales: id yyyy-MM y sin borrado', async () => {
  const db = alice();
  const snap = { assetsCents: 1000, liabilitiesCents: 0, updatedAt: now() };
  await assertSucceeds(setDoc(doc(db, 'users/alice/snapshots/2026-10'), snap));
  await assertSucceeds(setDoc(doc(db, 'users/alice/snapshots/2026-10'), { ...snap, assetsCents: 2000 }));
  await assertFails(setDoc(doc(db, 'users/alice/snapshots/octubre'), snap));
  await assertFails(deleteDoc(doc(db, 'users/alice/snapshots/2026-10')));
});

test('colecciones no previstas están cerradas', async () => {
  await assertFails(setDoc(doc(alice(), 'users/alice'), { a: 1 }));
  await assertFails(setDoc(doc(alice(), 'users/alice/otra/x'), { a: 1 }));
  await assertFails(setDoc(doc(alice(), 'publico/x'), { a: 1 }));
});

const recurrence = (o = {}) => ({
  type: 'movement', frequency: 'monthly', startDate: Timestamp.fromDate(new Date('2026-10-14')),
  accountId: 'acc1', kind: 'expense', amountCents: 1299, previousAmountCents: null, toAccountId: null,
  category: 'subscriptions', note: 'Netflix', count: null, endDate: null, nextIndex: 0, auto: true,
  principalCents: null, rateBps: null, months: null, payAccountId: null,
  createdAt: now(), updatedAt: now(), ...o,
});
const plan = (o = {}) => recurrence({
  type: 'installment', kind: null, amountCents: null, category: null, note: 'Portátil',
  principalCents: 120000, rateBps: 0, months: 12, payAccountId: 'acc1', accountId: 'loan1', ...o,
});

test('programaciones: crear, validar y bloquear de otros usuarios', async () => {
  const db = alice();
  await assertSucceeds(setDoc(doc(db, 'users/alice/recurrences/r1'), recurrence()));
  await assertSucceeds(setDoc(doc(db, 'users/alice/recurrences/p1'), plan()));
  await assertFails(setDoc(doc(db, 'users/alice/recurrences/r2'), recurrence({ frequency: 'diaria' })));
  await assertFails(setDoc(doc(db, 'users/alice/recurrences/r3'), recurrence({ amountCents: 0 })));
  await assertFails(setDoc(doc(db, 'users/alice/recurrences/r4'), recurrence({ auto: 'si' })));
  await assertFails(setDoc(doc(db, 'users/alice/recurrences/p2'), plan({ months: 0 })));
  await assertFails(setDoc(doc(db, 'users/alice/recurrences/p3'), plan({ rateBps: -5 })));
  await assertFails(setDoc(doc(db, 'users/alice/recurrences/p4'), plan({ payAccountId: null })));
  await assertFails(setDoc(doc(db, 'users/alice/recurrences/r5'), recurrence({ extra: 1 })));
  await assertFails(getDoc(doc(bob(), 'users/alice/recurrences/r1')));
});

test('programaciones: el contador solo avanza', async () => {
  const db = alice();
  const ref = doc(db, 'users/alice/recurrences/r1');
  await setDoc(ref, recurrence({ nextIndex: 3 }));
  await assertSucceeds(updateDoc(ref, { nextIndex: 4, updatedAt: now() }));
  await assertFails(updateDoc(ref, { nextIndex: 2, updatedAt: now() }));
});

test('apuntar una cuota: movimientos, saldos y contador a la vez (como la app)', async () => {
  const db = alice();
  await setDoc(doc(db, 'users/alice/accounts/acc1'), account({ balanceCents: 500000 }));
  await setDoc(doc(db, 'users/alice/accounts/loan1'), account({ name: 'Portátil', type: 'loan', balanceCents: 120000 }));
  await setDoc(doc(db, 'users/alice/recurrences/p1'), plan());
  const b = writeBatch(db);
  b.set(doc(db, 'users/alice/movements/p1-r0-c'), movement({ kind: 'transfer', amountCents: 10000, toAccountId: 'loan1', category: 'transfer' }));
  b.update(doc(db, 'users/alice/accounts/acc1'), { balanceCents: increment(-10000), updatedAt: now() });
  b.update(doc(db, 'users/alice/accounts/loan1'), { balanceCents: increment(-10000), updatedAt: now() });
  b.update(doc(db, 'users/alice/recurrences/p1'), { nextIndex: 1, updatedAt: now() });
  await assertSucceeds(b.commit());
});

test('objetivo dinámico: meses de gasto entre 1 y 24', async () => {
  const db = alice();
  await assertSucceeds(setDoc(doc(db, 'users/alice/goals/g1'), goal({ targetMonths: 6 })));
  await assertSucceeds(setDoc(doc(db, 'users/alice/goals/g2'), goal({ targetMonths: null })));
  await assertFails(setDoc(doc(db, 'users/alice/goals/g3'), goal({ targetMonths: 0 })));
  await assertFails(setDoc(doc(db, 'users/alice/goals/g4'), goal({ targetMonths: 6.5 })));
  await assertFails(setDoc(doc(db, 'users/alice/goals/g5'), goal({ targetMonths: 99 })));
});
