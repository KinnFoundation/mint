"reach 0.1";
"use strict";
// -----------------------------------------------
// Name: KINN Mint
// Version: 0.0.1 - initial
// Requires Reach v0.1.11-rc7 (27cb9643) or later
// ----------------------------------------------

import {
  State,
  api,
  view
} from '@KinnFoundation/sale#sale-v0.1.11r4:interface.rsh';

// TYPES

export const Params = Object({
  name: Bytes(32),
  symbol: Bytes(8),
  url: Bytes(96),
  metadata: Bytes(32),
  supply: UInt,
  decimals: UInt,
});

// CONTRACT

export const Event = () => [Events({ tokenLaunch: [] })];
export const Participants = () => [
  Participant("Manager", {
    getParams: Fun([], Params),
  }),
];
export const Views = () => [View(view(State))];
export const Api = () => [API(api)];
export const App = (map) => {
  const [{ amt, ttl }, [addr, _], [Manager], [v], [a], [e]] = map;
  Manager.only(() => {
    const { name, symbol, url, metadata, supply, decimals } = declassify(
      interact.getParams()
    );
  });
  Manager.publish(name, symbol, url, metadata, supply, decimals)
    .pay(amt)
    .timeout(relativeTime(ttl), () => {
      Anybody.publish();
      commit();
      exit();
    });
  transfer(amt).to(addr);
  const token = new Token({ name, symbol, url, metadata, supply, decimals });
  check(token.supply() === supply, "token has supply");
  e.tokenLaunch();
  const initialState = {
    manager: Manager,
    token,
    tokenAmount: supply,
    price: 3,
    closed: false,
  };
  const [s] = parallelReduce([initialState])
    .define(() => {
      v.state.set(State.fromObject(s));
    })
    .invariant(!token.destroyed())
    .invariant(implies(!s.closed, balance(token) == s.tokenAmount))
    .invariant(implies(s.closed, balance(token) == supply))
    .invariant(token.supply() == supply)
    .invariant(balance() == 0, "balance accurate")
    // BALANCE
    .while(!s.closed)
    .paySpec([token])
    // api: update
    //  - update price
    .api_(a.update, (msg) => {
      check(msg > 0, "price must be greater than 0");
      return [
        (k) => {
          k(null);
          return [
            {
              ...s,
              price: msg,
            },
          ];
        },
      ];
    })
    // api: grant
    //  - assign another account as manager
    .api_(a.grant, (msg) => {
      check(this === s.manager, "only manager can grant");
      return [
        (k) => {
          k(null);
          return [
            {
              ...s,
              manager: msg,
            },
          ];
        },
      ];
    })
    // api: buy
    //  - buy token
    .api_(a.buy, (msg) => {
      check(msg <= s.tokenAmount, "not enough tokens");
      return [
        [msg * s.price, [0, token]],
        (k) => {
          k(null);
          transfer(msg * s.price).to(s.manager);
          transfer(msg, token).to(this);
          return [
            {
              ...s,
              tokenAmount: s.tokenAmount - msg,
            },
          ];
        },
      ];
    })
    // api: eject
    .api_(a.close, () => {
      check(s.tokenAmount == 0, "cannot close until all tokens are sold");
      return [
        [amt, [supply, token]],
        (k) => {
          k(null);
          transfer(amt).to(addr);
          return [
            {
              ...s,
              closed: true,
              tokenAmount: supply,
            },
          ];
        },
      ];
    })
    .timeout(false);
  token.burn();
  token.destroy();
  commit();
  exit();
};
// ----------------------------------------------
